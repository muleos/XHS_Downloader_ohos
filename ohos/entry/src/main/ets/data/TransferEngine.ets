/**
 * Ported from data/network/ResumableTransfer.kt — resumable fetch with Range,
 * per-URL retry with exponential backoff, checkpoint files (.part/.json),
 * validator matching and media-type sniffing.
 */
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Context } from '@kit.AbilityKit';
import { XhsHttpClient } from '../core/XhsHttpClient';
import { MediaFileType } from '../core/MediaFileType';
import { Sha256 } from '../core/Sha256';

export enum TransferFailure {
  NETWORK = 0,
  ACCESS = 1,
  NON_MEDIA = 2,
  INCOMPLETE = 3,
  RANGE = 4,
  NO_SPACE = 5
}

export class TransferException extends Error {
  reason: TransferFailure;

  constructor(reason: TransferFailure, detail: string = '') {
    super(detail.length > 0 ? detail : 'transfer ' + reason);
    this.reason = reason;
  }
}

export class TransferredMedia {
  path: string;
  type: MediaFileType;

  constructor(path: string, type: MediaFileType) {
    this.path = path;
    this.type = type;
  }
}

export class Checkpoint {
  identity: string = '';
  total: number = 0;
  complete: boolean = false;
  validator: string = '';
}

interface HeaderState {
  status: number;
  total: number;
  validator: string;
  contentType: string;
  rangeFirst: number;
}

export class TransferEngine {
  private root: string;

  constructor(root: string) {
    this.root = root;
  }

  static fingerprint(value: string): string {
    return Sha256.digestHex(value);
  }

  async fetch(context: Context, urls: string[], targetName: string, retriesPerUrl: number,
    timeoutSeconds: number, onProgress: (received: number, total: number) => void,
    isCancelled: () => boolean): Promise<TransferredMedia> {
    try {
      fileIo.mkdirSync(this.root, true);
    } catch (e) {
    }
    const target = this.root + '/' + targetName;
    let lastDetail = '';
    for (const url of urls) {
      let attempt = 0;
      while (attempt <= retriesPerUrl) {
        if (isCancelled()) {
          throw new TransferException(TransferFailure.NETWORK, 'cancelled');
        }
        try {
          return await this.fetchOne(url, target, timeoutSeconds, onProgress, isCancelled);
        } catch (e) {
          const failure = e instanceof TransferException ? (e as TransferException) : null;
          if (failure !== null && (failure.reason === TransferFailure.NO_SPACE ||
            failure.reason === TransferFailure.NON_MEDIA)) {
            throw failure;
          }
          lastDetail = e instanceof Error ? e.message : String(e);
          attempt++;
          if (attempt > retriesPerUrl || isCancelled()) {
            break;
          }
          const backoff = Math.min(500 * Math.pow(2, attempt - 1), 15000);
          await TransferEngine.sleep(backoff);
        }
      }
    }
    throw new TransferException(TransferFailure.NETWORK, lastDetail.length > 0 ? lastDetail : 'all urls failed');
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private async fetchOne(url: string, target: string, timeoutSeconds: number,
    onProgress: (received: number, total: number) => void, isCancelled: () => boolean): Promise<TransferredMedia> {
    const part = target + '.part';
    const checkpointPath = target + '.json';
    const client = http.createHttp();
    let written = 0;
    let total = 0;
    let validator = '';
    let fd = -1;
    try {
      // Load checkpoint only when the part file exists.
      let cp: Checkpoint | null = null;
      let partSize = 0;
      try {
        partSize = fileIo.statSync(part).size;
        const stat = fileIo.statSync(checkpointPath);
        const f = fileIo.openSync(checkpointPath, fileIo.OpenMode.READ_ONLY);
        const buf = new ArrayBuffer(stat.size);
        fileIo.readSync(f.fd, buf);
        fileIo.closeSync(f.fd);
        const parsed = JSON.parse(String(buf)) as Checkpoint;
        if (parsed.identity === TransferEngine.fingerprint(url) && partSize > 0) {
          cp = parsed;
        }
      } catch (e) {
        cp = null;
      }
      written = cp !== null ? Math.min(partSize, cp.total) : 0;

      const headerState: HeaderState = { status: 0, total: 0, validator: '', contentType: '', rangeFirst: -1 };
      const headerPromise = new Promise<void>((resolve, reject) => {
        client.on('headersReceive', (value: Record<string, string>) => {
          try {
            const lower: Record<string, string> = {};
            for (const key of Object.keys(value)) {
              lower[key.toLowerCase()] = String(value[key]);
            }
            headerState.status = parseInt(lower['response_code'] !== undefined ? lower['response_code'] : '0', 10);
            headerState.contentType = lower['content-type'] !== undefined ? lower['content-type'] : '';
            headerState.validator = lower['etag'] !== undefined ? lower['etag'] :
              (lower['last-modified'] !== undefined ? lower['last-modified'] : '');
            const contentRange = lower['content-range'] !== undefined ? lower['content-range'] : '';
            const rangeMatch = contentRange.match(/bytes (\d+)-(\d+)\/(\d+)/);
            if (rangeMatch !== null) {
              headerState.rangeFirst = parseInt(rangeMatch[1], 10);
              headerState.total = parseInt(rangeMatch[3], 10);
            } else {
              headerState.total = parseInt(lower['content-length'] !== undefined ? lower['content-length'] : '0', 10);
            }
            const type = headerState.contentType.toLowerCase();
            if (type.startsWith('text/') || type.includes('json') || type.includes('xml')) {
              reject(new TransferException(TransferFailure.NON_MEDIA, headerState.contentType));
              return;
            }
            // Range validation: 206 must resume exactly at our offset; 200 restarts.
            if (headerState.status === 206 && headerState.rangeFirst !== written) {
              written = 0;
            } else if (headerState.status === 200) {
              written = 0;
            }
            if (rangeMatch !== null) {
              total = headerState.total;
            } else {
              total = written + headerState.total;
            }
            validator = headerState.validator;
            if (written === 0) {
              try {
                fileIo.unlinkSync(part);
              } catch (e) {
              }
              fd = fileIo.openSync(part, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
            } else {
              fd = fileIo.openSync(part, fileIo.OpenMode.READ_WRITE);
            }
            resolve();
          } catch (err) {
            reject(err instanceof Error ? err : new Error(String(err)));
          }
        });
        client.requestInStream(url, TransferEngine.options(written, cp, timeoutSeconds)).catch((e: BusinessError) => {
          reject(new Error(e.message !== undefined ? e.message : 'request failed'));
        });
      });

      const donePromise = new Promise<void>((resolve, reject) => {
        client.on('dataReceive', (chunk: ArrayBuffer) => {
          if (isCancelled()) {
            client.destroy();
            reject(new TransferException(TransferFailure.NETWORK, 'cancelled'));
            return;
          }
          if (chunk.byteLength <= 0 || fd < 0) {
            return;
          }
          try {
            fileIo.writeSync(fd, chunk, { offset: written, length: chunk.byteLength });
          } catch (e) {
            reject(new TransferException(TransferFailure.NO_SPACE, 'write failed'));
            return;
          }
          written += chunk.byteLength;
          onProgress(written, total);
        });
        client.on('dataEnd', () => {
          resolve();
        });
      });
      await headerPromise;
      await donePromise;
      if (total > 0 && written !== total) {
        throw new TransferException(TransferFailure.INCOMPLETE, written + '/' + total);
      }
      const detected = TransferEngine.sniff(part);
      if (detected === null) {
        throw new TransferException(TransferFailure.NON_MEDIA, 'unknown signature');
      }
      fileIo.renameSync(part, target);
      TransferEngine.persistCheckpoint(checkpointPath, TransferEngine.checkpoint(url, total, validator));
      return new TransferredMedia(target, detected);
    } finally {
      if (fd >= 0) {
        fileIo.closeSync(fd);
      }
      try {
        client.off('dataReceive');
        client.off('dataEnd');
        client.off('headersReceive');
      } catch (e) {
      }
      client.destroy();
    }
  }

  private static options(written: number, cp: Checkpoint | null, timeoutSeconds: number): http.HttpRequestOptions {
    const header: Record<string, string> = { 'User-Agent': XhsHttpClient.USER_AGENT };
    if (written > 0 && cp !== null) {
      header['Range'] = 'bytes=' + written + '-';
      if (cp.validator.length > 0) {
        header['If-Range'] = cp.validator;
      }
    }
    return {
      method: http.RequestMethod.GET,
      header: header,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      usingCache: false,
      connectTimeout: timeoutSeconds * 1000,
      readTimeout: timeoutSeconds * 1000
    };
  }

  private static checkpoint(url: string, total: number, validator: string): Checkpoint {
    const cp = new Checkpoint();
    cp.identity = TransferEngine.fingerprint(url);
    cp.total = total;
    cp.complete = true;
    cp.validator = validator;
    return cp;
  }

  private static persistCheckpoint(path: string, cp: Checkpoint): void {
    try {
      const temporary = path + '.tmp';
      const f = fileIo.openSync(temporary, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, JSON.stringify(cp));
      fileIo.closeSync(f.fd);
      fileIo.renameSync(temporary, path);
    } catch (e) {
      // Checkpoint is best-effort.
    }
  }

  private static sniff(path: string): MediaFileType | null {
    const f = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const buf = new ArrayBuffer(64);
      const read = fileIo.readSync(f.fd, buf);
      return MediaFileType.detect(buf.slice(0, read));
    } finally {
      fileIo.closeSync(f.fd);
    }
  }
}
