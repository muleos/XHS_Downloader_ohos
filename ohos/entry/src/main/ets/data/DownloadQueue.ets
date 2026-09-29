/**
 * Sequential download queue — simplified port of domain/download/DownloadQueue.kt.
 * v1 downloads to cacheDir temp files; the save step (gallery/files) runs after,
 * because security-component authorization (SaveButton) only covers the save call.
 */
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Context } from '@kit.AbilityKit';
import { MediaFileType } from '../core/MediaFileType';
import { XhsHttpClient } from '../core/XhsHttpClient';
import { NamingFormat } from '../core/NamingFormat';
import { ResolvedNote } from '../core/models';

export enum TaskState {
  PENDING = 0,
  RUNNING = 1,
  DONE = 2,
  FAILED = 3,
  CANCELLED = 4
}

export class QueueItem {
  id: number;
  url: string;
  isVideo: boolean;
  displayName: string;
  mediaId: string;
  state: TaskState = TaskState.PENDING;
  totalBytes: number = 0;
  receivedBytes: number = 0;
  speedBps: number = 0;
  error: string = '';
  tempPath: string = '';

  constructor(id: number, url: string, isVideo: boolean, displayName: string, mediaId: string) {
    this.id = id;
    this.url = url;
    this.isVideo = isVideo;
    this.displayName = displayName;
    this.mediaId = mediaId;
  }
}

export class QueueSnapshot {
  items: QueueItem[] = [];
  running: boolean = false;
}

type QueueListener = (snapshot: QueueSnapshot) => void;

export class DownloadQueue {
  private items: QueueItem[] = [];
  private running: boolean = false;
  private cancelled: Set<number> = new Set();
  private inFlight: http.HttpRequest | null = null;
  private listeners: QueueListener[] = [];
  private nextId: number = 1;

  private client: XhsHttpClient;
  private context: Context | null = null;

  constructor(client: XhsHttpClient) {
    this.client = client;
  }

  init(context: Context): void {
    this.context = context;
  }

  onChange(listener: QueueListener): void {
    this.listeners.push(listener);
  }

  private notify(): void {
    const snap = new QueueSnapshot();
    snap.items = this.items;
    snap.running = this.running;
    for (const l of this.listeners) {
      l(snap);
    }
  }

  count(): number {
    return this.items.length;
  }

  /** Enqueue every unresolved media of a note; skips URLs already queued. */
  enqueueNote(note: ResolvedNote, template: string, includeCommentImages: boolean): number {
    let added = 0;
    const entries: Array<[string, boolean, string]> = [];
    let index = 0;
    const total = note.items.length;
    for (const item of note.items) {
      index++;
      if (item.live !== null) {
        entries.push([item.live.image.sourceUrl, false,
          NamingFormat.render(template, note, index - 1, total, 'jpg')]);
        entries.push([item.live.video.sourceUrl, true,
          NamingFormat.render(template, note, index - 1, total, 'mp4')]);
      } else if (item.image !== null) {
        entries.push([item.image.sourceUrl, false,
          NamingFormat.render(template, note, index - 1, total, 'jpg')]);
      } else if (item.video !== null) {
        entries.push([item.video.sourceUrl, true,
          NamingFormat.render(template, note, index - 1, total, 'mp4')]);
      }
    }
    for (const entry of entries) {
      if (!includeCommentImages && entry[2].indexOf('comment') >= 0) {
        continue;
      }
      if (this.hasUrl(entry[0])) {
        continue;
      }
      const qi = new QueueItem(this.nextId++, entry[0], entry[1], entry[2], note.noteId);
      this.items.push(qi);
      added++;
    }
    this.notify();
    return added;
  }

  hasUrl(url: string): boolean {
    for (const item of this.items) {
      if (item.url === url) {
        return true;
      }
    }
    return false;
  }

  /** Enqueue a single media entry from the Detail page selection. */
  add(url: string, isVideo: boolean, displayName: string, mediaId: string): boolean {
    return this.pushOne(url, isVideo, displayName, mediaId);
  }

  private pushOne(url: string, isVideo: boolean, displayName: string, mediaId: string): boolean {
    if (this.hasUrl(url)) {
      return false;
    }
    this.items.push(new QueueItem(this.nextId++, url, isVideo, displayName, mediaId));
    this.notify();
    return true;
  }

  clearFinished(): void {
    this.items = this.items.filter((i: QueueItem): boolean =>
      i.state !== TaskState.DONE && i.state !== TaskState.CANCELLED && i.state !== TaskState.FAILED);
    this.notify();
  }

  cancel(id: number): void {
    const item = this.byId(id);
    if (item === null) {
      return;
    }
    if (item.state === TaskState.RUNNING) {
      this.cancelled.add(id);
      if (this.inFlight !== null) {
        this.inFlight.destroy();
        this.inFlight = null;
      }
      item.state = TaskState.CANCELLED;
    } else if (item.state === TaskState.PENDING) {
      item.state = TaskState.CANCELLED;
    }
    this.notify();
  }

  retry(id: number): void {
    const item = this.byId(id);
    if (item !== null && (item.state === TaskState.FAILED || item.state === TaskState.CANCELLED)) {
      item.state = TaskState.PENDING;
      item.error = '';
      item.receivedBytes = 0;
      this.notify();
      this.start(this.useWebSessionFlag, this.timeoutSecondsFlag);
    }
  }

  private useWebSessionFlag: boolean = true;
  private timeoutSecondsFlag: number = 45;

  async start(useWebSession: boolean, timeoutSeconds: number): Promise<void> {
    if (this.running) {
      return;
    }
    this.useWebSessionFlag = useWebSession;
    this.timeoutSecondsFlag = timeoutSeconds;
    this.running = true;
    this.notify();
    for (const item of this.items) {
      if (item.state !== TaskState.PENDING) {
        continue;
      }
      await this.runOne(item);
    }
    this.running = false;
    this.notify();
  }

  private async runOne(item: QueueItem): Promise<void> {
    item.state = TaskState.RUNNING;
    item.error = '';
    this.notify();
    if (this.context === null) {
      item.state = TaskState.FAILED;
      item.error = 'no context';
      this.notify();
      return;
    }
    const tempPath = this.context.cacheDir + '/dl_' + item.id + '.bin';
    item.tempPath = tempPath;
    try {
      const file = fileIo.openSync(tempPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const client = http.createHttp();
      this.inFlight = client;
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': XhsHttpClient.USER_AGENT,
          'Referer': 'https://www.xiaohongshu.com/'
        } as Record<string, string>,
        connectTimeout: this.timeoutSecondsFlag * 1000,
        readTimeout: this.timeoutSecondsFlag * 1000,
        usingCache: false
      };
      const cookie = this.client.cookieHeaderFor(item.url, this.useWebSessionFlag);
      if (cookie.length > 0) {
        (options.header as Record<string, string>)['Cookie'] = cookie;
      }
      let offset = 0;
      let lastTick = Date.now();
      let lastBytes = 0;
      await new Promise<void>((resolve: () => void, reject: (e: Error) => void) => {
        client.on('headersReceive', (headers: Record<string, string>) => {
          const lengthHeader = headers['content-length'] !== undefined ? headers['content-length'] : headers['Content-Length'];
          if (lengthHeader !== undefined) {
            item.totalBytes = Number(lengthHeader);
          }
        });
        client.on('dataReceive', (chunk: ArrayBuffer) => {
          if (this.cancelled.has(item.id)) {
            return;
          }
          fileIo.writeSync(file.fd, chunk, { offset: offset, length: chunk.byteLength });
          offset += chunk.byteLength;
          item.receivedBytes = offset;
          const now = Date.now();
          if (now - lastTick > 500) {
            item.speedBps = Math.round((offset - lastBytes) * 1000 / Math.max(1, now - lastTick));
            lastTick = now;
            lastBytes = offset;
            this.notify();
          }
        });
        client.on('dataEnd', () => {
          resolve();
        });
        client.requestInStream(item.url, options).catch((e: BusinessError) => {
          reject(new Error(e.message !== undefined ? e.message : 'stream error'));
        });
      });
      if (this.cancelled.has(item.id)) {
        fileIo.closeSync(file.fd);
        fileIo.unlinkSync(tempPath);
        item.tempPath = '';
        this.notify();
        return;
      }
      fileIo.closeSync(file.fd);
      // Sniff the real type; correct the extension when the CDN lies.
      const probe = fileIo.readSync(file.fd, new ArrayBuffer(64));
      const detected = MediaFileType.detect(probe.buffer);
      if (detected !== null) {
        const dot = item.displayName.lastIndexOf('.');
        const base = dot > 0 ? item.displayName.substring(0, dot) : item.displayName;
        item.displayName = base + '.' + detected.extension;
      }
      item.state = TaskState.DONE;
      this.notify();
    } catch (e) {
      if (this.cancelled.has(item.id)) {
        item.state = TaskState.CANCELLED;
      } else {
        item.state = TaskState.FAILED;
        item.error = e instanceof Error ? e.message : String(e);
      }
      this.notify();
    } finally {
      this.inFlight = null;
    }
  }

  private byId(id: number): QueueItem | null {
    for (const item of this.items) {
      if (item.id === id) {
        return item;
      }
    }
    return null;
  }
}
