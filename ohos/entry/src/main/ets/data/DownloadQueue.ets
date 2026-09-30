/**
 * Ported from domain/download/DownloadQueue.kt — durable task draining with
 * 4-way media parallelism, recordKey skip, live photo composition pipeline,
 * note text export and partial-failure preservation.
 */
import { Context } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { AppContainer } from './AppContainer';
import { SettingsStore } from './SettingsStore';
import { RecordStore } from './RecordStore';
import { TaskStore, DownloadTask, TaskStatus, TaskResource, ResourceState, TaskSession } from './TaskStore';
import { TransferEngine, TransferException, TransferredMedia } from './TransferEngine';
import { MediaSaver, StoredOutput, FolderSaveRequest } from './MediaSaver';
import { LivePhotoComposer } from '../core/LivePhotoComposer';
import { NoteOutput } from '../core/NoteOutput';
import { XhsContentRepository } from '../core/XhsContentRepository';
import { AppSettings, DownloadOptions, ResolvedNote, ResolvedNoteItem, LivePhotoMode, DownloadRecord } from '../core/models';
import { XhsHttpClient } from '../core/XhsHttpClient';
import { XhsUrlParser } from '../core/XhsUrlParser';
import { MediaFileType } from '../core/MediaFileType';
import { SavedItem, Platform, WorkType } from '../model/SaveModels';
import { wantAgent } from '@kit.AbilityKit';

export class QueueListenerState {
  tasks: DownloadTask[] = [];
  speedBps: number = 0;
  running: boolean = false;
}

/** Aggregated result of a save action (gallery or folder). */
export class SaveResult {
  saved: number = 0;
  alreadySaved: number = 0;
  error: string = '';
}

export class DownloadQueue {
  private client: XhsHttpClient | null = null;
  private store: TaskStore = new TaskStore();
  private records: RecordStore | null = null;
  private settings: SettingsStore | null = null;
  private repo: XhsContentRepository | null = null;
  private saver: MediaSaver = new MediaSaver();
  private context: Context | null = null;
  private listeners: Array<(state: QueueListenerState) => void> = [];
  private draining = false;
  private cancelledResources: Set<string> = new Set<string>();
  private paused: boolean = false;
  private lastSpeed = 0;

  constructor(client: XhsHttpClient) {
    this.client = client;
  }

  private requireContext(): Context {
    if (this.context === null) {
      throw new Error('context not initialized');
    }
    return this.context;
  }

  private requireRecords(): RecordStore {
    if (this.records === null) {
      throw new Error('records not initialized');
    }
    return this.records;
  }

  private requireSettings(): SettingsStore {
    if (this.settings === null) {
      throw new Error('settings not initialized');
    }
    return this.settings;
  }

  async init(context: Context, settings: SettingsStore, records: RecordStore, repo: XhsContentRepository): Promise<void> {
    this.context = context;
    this.settings = settings;
    this.records = records;
    this.repo = repo;
    await this.store.init(context);
  }

  get tasks(): TaskStore {
    return this.store;
  }

  onChange(listener: (state: QueueListenerState) => void): void {
    this.listeners.push(listener);
    this.notify();
  }

  private notify(): void {
    const state = new QueueListenerState();
    state.tasks = this.store.all();
    state.speedBps = this.lastSpeed;
    state.running = this.draining;
    for (const listener of this.listeners) {
      listener(state);
    }
  }

  /** Enqueue raw share text (single or multi-link). */
  enqueue(rawInput: string, infoOnly: boolean = false): number[] {
    const links = this.linksFrom(rawInput);
    const ids: number[] = [];
    for (const link of links) {
      const task = this.store.create(link);
      task.session.rawInput = link;
      task.session.infoOnly = infoOnly;
      task.session.options = this.currentOptions();
      this.store.touch(task);
      ids.push(task.id);
    }
    this.notify();
    this.drain();
    return ids;
  }

  /** Enqueue a resolved note for selective download (Detail page). */
  enqueueForSelection(note: ResolvedNote): number {
    const task = this.store.create(note.canonicalUrl);
    task.session.rawInput = note.canonicalUrl;
    task.session.options = this.currentOptions();
    task.session.resolvedJson = JSON.stringify(note.toBundle());
    task.session.requireSelection = true;
    task.noteTitle = note.title;
    task.noteType = note.type;
    task.status = TaskStatus.WAITING_FOR_USER;
    this.store.touch(task);
    this.notify();
    return task.id;
  }

  confirmSelection(taskId: number, selected: number[]): void {
    const task = this.store.byId(taskId);
    if (task === null) {
      return;
    }
    task.session.selected = selected;
    task.session.requireSelection = false;
    task.status = TaskStatus.QUEUED;
    this.store.touch(task);
    this.notify();
    this.drain();
  }

  cancel(taskId: number): void {
    const task = this.store.byId(taskId);
    if (task === null) {
      return;
    }
    for (const res of task.resources) {
      if (res.state === ResourceState.DOWNLOADING) {
        this.cancelledResources.add(task.id + '/' + res.mediaId);
      }
    }
    task.status = TaskStatus.CANCELLED;
    task.active = false;
    this.store.touch(task);
    this.notify();
  }

  pause(taskId: number): void {
    const task = this.store.byId(taskId);
    if (task === null) {
      return;
    }
    if (task.status === TaskStatus.DOWNLOADING || task.status === TaskStatus.RESOLVING ||
      task.status === TaskStatus.QUEUED) {
      task.status = TaskStatus.PAUSED;
      task.active = false;
      for (const res of task.resources) {
        if (res.state === ResourceState.DOWNLOADING) {
          this.cancelledResources.add(task.id + '/' + res.mediaId);
        }
      }
      this.store.touch(task);
      this.notify();
    }
  }

  resume(taskId: number): void {
    const task = this.store.byId(taskId);
    if (task === null) {
      return;
    }
    if (task.status === TaskStatus.PAUSED) {
      task.status = TaskStatus.QUEUED;
      this.store.touch(task);
      this.notify();
      this.drain();
    }
  }

  retry(taskId: number): void {
    const task = this.store.byId(taskId);
    if (task === null) {
      return;
    }
    for (const res of task.resources) {
      if (res.state === ResourceState.FAILED) {
        res.state = ResourceState.DOWNLOADING;
        res.claimed = false; // claimNext skips claimed resources otherwise
      }
    }
    task.status = task.resources.length > 0 ? TaskStatus.DOWNLOADING : TaskStatus.QUEUED;
    task.errorMessage = '';
    this.store.touch(task);
    this.notify();
    this.drain();
  }

  private linksFrom(rawInput: string): string[] {
    return XhsUrlParser.extractLinks(rawInput);
  }

  private currentOptions(): DownloadOptions {
    const s: AppSettings = this.settings !== null ? this.settings.get() : new AppSettings();
    return s.downloadOptions;
  }

  private async startBackground(): Promise<void> {
    try {
      const ctx = AppContainer.get().abilityContext;
      if (ctx === null) {
        return;
      }
      const info: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: 'com.hmos.collection', abilityName: 'EntryAbility' }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(ctx, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
    } catch (e) {
      // Best-effort: in-app download still works without the continuous task.
    }
  }

  private async stopBackground(): Promise<void> {
    try {
      const ctx = AppContainer.get().abilityContext;
      if (ctx === null) {
        return;
      }
      await backgroundTaskManager.stopBackgroundRunning(ctx);
    } catch (e) {
    }
  }

  private async drain(): Promise<void> {
    if (this.draining) {
      return;
    }
    this.draining = true;
    this.notify();
    await this.startBackground();
    try {
      while (true) {
        const task = this.nextQueued();
        if (task === null) {
          break;
        }
        await this.runTask(task);
      }
    } finally {
      this.draining = false;
      this.lastSpeed = 0;
      await this.stopBackground();
      this.notify();
    }
  }

  private nextQueued(): DownloadTask | null {
    for (const task of this.store.all()) {
      if (task.status === TaskStatus.QUEUED || task.status === TaskStatus.DOWNLOADING ||
        task.status === TaskStatus.RESOLVING) {
        return task;
      }
    }
    return null;
  }

  private async runTask(task: DownloadTask): Promise<void> {
    const app = AppContainer.get();
    const options: DownloadOptions = task.session.options !== null ? task.session.options : this.currentOptions();
    task.active = true;
    try {
      // 1) Resolve if needed.
      let note = this.store.loadNote(task);
      if (note === null) {
        task.status = TaskStatus.RESOLVING;
        this.store.touch(task);
        this.notify();
        note = await AppContainer.get().repo.resolve(task.noteUrl, options.useWebSession, options.timeoutSeconds);
        task.session.resolvedJson = JSON.stringify(note.toBundle());
        task.noteTitle = note.title;
        task.noteType = note.type;
      }
      task.noteTitle = note.title.length > 0 ? note.title : note.noteId;

      // 2) Note text only / text export.
      const remark = this.store.remark(note.authorId);
      const folders = NoteOutput.folders(note, options, remark);
      if (task.session.infoOnly) {
        await this.saveTextOutputs(task, note, folders, options);
        task.status = TaskStatus.COMPLETED;
        this.store.touch(task);
        this.requireRecords().add(new DownloadRecord(task.id, note.noteId, note.authorName, note.title, '', 'info', Date.now()));
        return;
      }

      // 3) Build resource plan.
      if (task.resources.length === 0) {
        task.resources = this.planResources(task, note, options);
        task.totalFiles = task.resources.length;
        this.store.touch(task);
      }
      if (task.resources.length === 0) {
        task.status = TaskStatus.FAILED;
        task.errorMessage = 'no media';
        this.store.touch(task);
        this.notify();
        return;
      }

      // 4) Transfer with 4-way parallelism.
      task.status = TaskStatus.DOWNLOADING;
      this.store.touch(task);
      this.notify();
      const cacheDir = this.requireContext().cacheDir + '/xhsdn/' + task.id;
      await this.transferAll(task, note, options, cacheDir, folders);

      // 5) Publish results (skipped/completed already recorded inside transferAll).
      let completed = 0;
      let failed = 0;
      let skipped = 0;
      for (const res of task.resources) {
        if (res.state === ResourceState.COMPLETED) {
          completed++;
        } else if (res.state === ResourceState.SKIPPED) {
          skipped++;
        } else if (res.state === ResourceState.FAILED) {
          failed++;
        }
      }
      this.requireRecords().add(new DownloadRecord(task.id, note.noteId, note.authorName, note.title, '', 'downloaded', Date.now()));
      // Register completed media in the persistent library for the home feed.
      this.registerToLibrary(task, note, options);
      if (failed === 0) {
        task.status = completed === 0 && skipped > 0 ? TaskStatus.SKIPPED : TaskStatus.COMPLETED;
      } else if (completed + skipped > 0) {
        task.status = TaskStatus.PARTIAL;
      } else {
        task.status = TaskStatus.FAILED;
        task.errorMessage = 'all resources failed';
      }
      this.store.touch(task);
    } catch (e) {
      task.active = false;
      task.errorMessage = e instanceof Error ? e.message : String(e);
      if (e instanceof TransferException && (e as TransferException).reason === 2) {
        task.status = TaskStatus.FAILED;
      } else {
        task.status = TaskStatus.FAILED;
      }
      this.store.touch(task);
    } finally {
      task.active = false;
      this.store.touch(task);
      this.notify();
    }
  }

  /** Copies completed cache files into the persistent media library (home feed). */
  private registerToLibrary(task: DownloadTask, note: ResolvedNote, options: DownloadOptions): void {
    try {
      const done: TaskResource[] = [];
      for (const res of task.resources) {
        if ((res.state === ResourceState.COMPLETED || res.state === ResourceState.SKIPPED) &&
          res.tempPath.length > 0 && res.ext !== 'txt' && res.ext !== 'md') {
          done.push(res);
        }
      }
      if (done.length === 0) {
        return;
      }
      const dir = this.requireContext().filesDir + '/media';
      try {
        fileIo.mkdirSync(dir, true);
      } catch (e) {
      }
      const item = new SavedItem();
      item.id = 'xhs_' + note.noteId + '_' + task.id;
      item.platform = Platform.XHS;
      item.workType = note.type === 'video' ? WorkType.VIDEO : WorkType.IMAGES;
      item.title = note.title.length > 0 ? note.title : note.noteId;
      if (item.title.length > 80) {
        item.title = item.title.substring(0, 80);
      }
      item.author = note.authorName;
      item.sourceUrl = note.canonicalUrl;
      item.createTime = Date.now();
      const seen: string[] = [];
      for (const res of done) {
        const ext = res.ext === 'mp4' ? 'mp4' : 'jpg';
        const dest = dir + '/' + item.id + '_' + item.mediaPaths.length + '.' + ext;
        try {
          if (fileIo.accessSync(res.tempPath)) {
            if (fileIo.accessSync(dest)) {
              fileIo.unlinkSync(dest);
            }
            fileIo.copyFileSync(res.tempPath, dest);
            if (seen.indexOf(dest) < 0) {
              seen.push(dest);
              item.mediaPaths.push(dest);
            }
            if (item.coverPath.length === 0 && ext === 'jpg') {
              item.coverPath = dest;
            }
          }
        } catch (e) {
          // Skip this file.
        }
      }
      if (item.mediaPaths.length > 0) {
        AppContainer.get().saved.add(item);
      }
    } catch (e) {
      // Library registration is best-effort.
    }
  }

  private planResources(task: DownloadTask, note: ResolvedNote, options: DownloadOptions): TaskResource[] {
    const settings: AppSettings = this.requireSettings().get();
    const resources: TaskResource[] = [];
    const folders = NoteOutput.folders(note, options, this.store.remark(note.authorId));
    const forSelection = task.session.requireSelection || task.session.selected.length > 0;
    for (let i = 0; i < note.items.length; i++) {
      const item = note.items[i];
      if (forSelection) {
        if (task.session.selected.indexOf(i) < 0) {
          continue;
        }
      } else if (!NoteOutput.isEligibleItem(note, i, options, false)) {
        continue;
      }
      const mediaId = note.noteId + ':' + i;
      const key = NoteOutput.recordKey(note.noteId, mediaId, settings, folders);
      const baseName = NoteOutput.fileName(note, settings, i, 'jpg', Date.now());
      if (options.skipExisting && this.store.hasCompletedKey(key)) {
        const skipped = new TaskResource();
        skipped.mediaId = mediaId;
        skipped.recordKey = key;
        skipped.name = baseName;
        skipped.state = ResourceState.SKIPPED;
        resources.push(skipped);
        continue;
      }
      if (item.kind === 'image' && item.image !== null) {
        const r = new TaskResource();
        r.mediaId = mediaId;
        r.recordKey = key;
        r.ext = 'jpg';
        r.name = baseName;
        r.refsJson = JSON.stringify(NoteOutput.imageUrls(item.image, options.imageFormat));
        resources.push(r);
      } else if (item.kind === 'video' && item.video !== null) {
        const r = new TaskResource();
        r.mediaId = mediaId;
        r.recordKey = key;
        r.ext = 'mp4';
        r.name = NoteOutput.fileName(note, settings, i, 'mp4', Date.now());
        r.refsJson = JSON.stringify(NoteOutput.videoUrls(item.video, options.videoPreference));
        resources.push(r);
      } else if (item.kind === 'live' && item.live !== null) {
        const r = new TaskResource();
        r.mediaId = mediaId;
        r.recordKey = key;
        r.ext = 'jpg';
        r.livePair = true;
        r.name = baseName;
        const urls: string[] = NoteOutput.imageUrls(item.live.image, options.imageFormat);
        r.refsJson = JSON.stringify([urls[0], item.live.video.sourceUrl]);
        resources.push(r);
      }
    }
    return resources;
  }

  private async transferAll(task: DownloadTask, note: ResolvedNote, options: DownloadOptions,
    cacheDir: string, folders: string[]): Promise<void> {
    const engine = new TransferEngine(cacheDir);
    const parallel = 4;
    const workers: Promise<void>[] = [];
    const runWorker = async (): Promise<void> => {
      while (true) {
        const mine = this.claimNext(task);
        if (mine === null) {
          return;
        }
        await this.runResource(task, note, options, engine, mine, cacheDir, folders);
      }
    };
    for (let w = 0; w < parallel; w++) {
      workers.push(runWorker());
    }
    await Promise.all(workers);
  }

  private claimNext(task: DownloadTask): TaskResource | null {
    for (const res of task.resources) {
      if (res.state === ResourceState.DOWNLOADING && !res.claimed &&
        !this.cancelledResources.has(task.id + '/' + res.mediaId)) {
        res.claimed = true;
        return res;
      }
    }
    return null;
  }

  private async runResource(task: DownloadTask, note: ResolvedNote, options: DownloadOptions,
    engine: TransferEngine, res: TaskResource, cacheDir: string, folders: string[]): Promise<void> {
    if (this.cancelledResources.has(task.id + '/' + res.mediaId)) {
      res.state = ResourceState.FAILED;
      return;
    }
    try {
      const urls = res.refsJson.length > 0 ? (JSON.parse(res.refsJson) as string[]) : [res.name];
      const media = await engine.fetch(this.requireContext(), urls, res.mediaId + '.' + res.ext,
        options.maxRetries, options.timeoutSeconds,
        (received: number, total: number) => {
          res.bytes = received;
          this.recomputeProgress(task);
          this.notifyThrottled();
        },
        () => this.cancelledResources.has(task.id + '/' + res.mediaId));
      res.tempPath = media.path;
      // Align the extension with the sniffed payload (CDN may serve webp even
      // when the planned name says .jpg).
      if (media.type.extension.length > 0 && media.type.extension !== res.ext) {
        res.ext = media.type.extension;
        const dot = res.name.lastIndexOf('.');
        if (dot > 0) {
          res.name = res.name.substring(0, dot) + '.' + res.ext;
        }
      }
      try {
        const stored = await this.publish(task, note, options, media, res, folders);
        res.name = stored.name;
        res.savedUri = stored.uri;
        this.store.markCompletedKey(res.recordKey);
      } catch (publishError) {
        // Gallery writes need security-component authorization; the file stays
        // in cache until the user taps the save button (see saveCompleted()).
        const warnings: string[] = res.warnings.length > 0 ? (JSON.parse(res.warnings) as string[]) : [];
        warnings.push(publishError instanceof Error ? publishError.message : String(publishError));
        res.warnings = JSON.stringify(warnings);
      }
      res.state = ResourceState.COMPLETED;
    } catch (e) {
      res.state = ResourceState.FAILED;
      const detail = e instanceof Error ? e.message : String(e);
      const warnings: string[] = res.warnings.length > 0 ? (JSON.parse(res.warnings) as string[]) : [];
      warnings.push(detail);
      res.warnings = JSON.stringify(warnings);
    }
    this.recomputeProgress(task);
    this.store.touch(task);
    this.notify();
  }

  /** Publishes cached files to the gallery (system creation dialog, then fallback). */
  async saveCompleted(context: Context, taskId: number): Promise<SaveResult> {
    const result = new SaveResult();
    const task = this.store.byId(taskId);
    if (task === null) {
      result.error = 'task not found';
      return result;
    }
    const note = this.store.loadNote(task);
    if (note === null) {
      result.error = 'note not cached';
      return result;
    }
    const options = task.session.options !== null ? task.session.options : this.currentOptions();
    const folders = NoteOutput.folders(note, options, this.store.remark(note.authorId));
    const pending: TaskResource[] = [];
    for (const res of task.resources) {
      if (res.state !== ResourceState.COMPLETED || res.tempPath.length === 0) {
        continue;
      }
      if (res.savedUri.length > 0) {
        result.alreadySaved++;
      } else {
        pending.push(res);
      }
    }
    if (pending.length > 0) {
      let dialogError = '';
      try {
        // Primary: one system dialog per chunk of files.
        const files: FolderSaveRequest[] = pending.map((res: TaskResource): FolderSaveRequest => {
          const f = new FolderSaveRequest();
          f.path = res.tempPath;
          f.name = res.name;
          return f;
        });
        const created = await MediaSaver.storeGalleryBatch(context, files);
        if (created > 0) {
          result.saved += created;
          for (const res of pending) {
            res.savedUri = 'gallery://created';
          }
        } else {
          result.error = 'cancelled';
        }
      } catch (e) {
        dialogError = e instanceof Error ? e.message : String(e);
      }
      if (result.saved === 0) {
        // Fallback: per-file applyChanges (needs security-component authorization).
        let lastError = dialogError;
        for (const res of pending) {
          try {
            const type = new MediaFileType(res.ext, res.ext === 'mp4' ? 'video/mp4' : 'image/jpeg');
            const stored = await MediaSaver.storeArchived(context, res.tempPath, type, res.name,
              folders, options, res.mediaId);
            res.savedUri = stored.uri;
            result.saved++;
          } catch (e2) {
            lastError = e2 instanceof Error ? e2.message : String(e2);
          }
        }
        if (result.saved === 0 && lastError.length > 0) {
          result.error = lastError;
        }
      }
    }
    this.store.touch(task);
    this.notify();
    return result;
  }

  /** Copies cached files into a user-chosen system folder via the document picker. */
  async saveCompletedToFolder(context: Context, taskId: number): Promise<SaveResult> {
    const result = new SaveResult();
    const task = this.store.byId(taskId);
    if (task === null) {
      result.error = 'task not found';
      return result;
    }
    const files: FolderSaveRequest[] = [];
    for (const res of task.resources) {
      if (res.state !== ResourceState.COMPLETED || res.tempPath.length === 0) {
        continue;
      }
      const f = new FolderSaveRequest();
      f.path = res.tempPath;
      f.name = res.name;
      files.push(f);
    }
    if (files.length === 0) {
      result.error = 'nothing downloaded yet';
      return result;
    }
    try {
      const outs = await MediaSaver.storeToFolder(files);
      result.saved = outs.length;
      if (outs.length === 0) {
        result.error = 'cancelled';
      }
    } catch (e) {
      result.error = e instanceof Error ? e.message : String(e);
    }
    return result;
  }

  private async publish(task: DownloadTask, note: ResolvedNote, options: DownloadOptions,
    media: TransferredMedia, res: TaskResource, folders: string[]): Promise<StoredOutput> {
    if (res.livePair) {
      return this.publishLivePhoto(task, note, options, media, res, folders);
    }
    return MediaSaver.storeArchived(this.requireContext(), media.path, media.type, res.name,
      folders, options, res.mediaId);
  }

  private async publishLivePhoto(task: DownloadTask, note: ResolvedNote, options: DownloadOptions,
    media: TransferredMedia, res: TaskResource, folders: string[]): Promise<StoredOutput> {
    const plan = JSON.parse(res.refsJson) as string[];
    const imageUrl = plan[0];
    const videoUrl = plan[1];
    const cacheDir = this.requireContext().cacheDir + '/xhsdn/' + task.id;
    const engine = new TransferEngine(cacheDir);
    const baseName = res.name.replace(/\.[a-z0-9]+$/i, '');
    const mode = options.livePhotoMode;
    const warning = 'livephoto_fallback_separate';
    if (mode === LivePhotoMode.STILL) {
      const imageMedia = await engine.fetch(this.requireContext(), [imageUrl], baseName + '_still_in.jpg',
        options.maxRetries, options.timeoutSeconds, () => {
        }, () => false);
      return MediaSaver.storeArchived(this.requireContext(), imageMedia.path, imageMedia.type, baseName + '.jpg',
        folders, options, res.mediaId);
    }
    if (mode === LivePhotoMode.SEPARATE) {
      const imageMedia = await engine.fetch(this.requireContext(), [imageUrl], baseName + '_img_in.jpg',
        options.maxRetries, options.timeoutSeconds, () => {
        }, () => false);
      const videoMedia = await engine.fetch(this.requireContext(), [videoUrl], baseName + '_vid_in.mp4',
        options.maxRetries, options.timeoutSeconds, () => {
        }, () => false);
      const imgOut = await MediaSaver.storeArchived(this.requireContext(), imageMedia.path, imageMedia.type,
        baseName + '.jpg', folders, options, res.mediaId + '_img');
      const vidOut = await MediaSaver.storeArchived(this.requireContext(), videoMedia.path, videoMedia.type,
        baseName + '.mp4', folders, options, res.mediaId + '_vid');
      return imgOut;
    }
    // MERGED with composition + fallback to separate.
    try {
      const imageMedia = await engine.fetch(this.requireContext(), [imageUrl], baseName + '_c_in.jpg',
        options.maxRetries, options.timeoutSeconds, () => {
        }, () => false);
      const videoMedia = await engine.fetch(this.requireContext(), [videoUrl], baseName + '_c_in.mp4',
        options.maxRetries, options.timeoutSeconds, () => {
        }, () => false);
      const videoSize = fileIo.statSync(videoMedia.path).size;
      const imgFd = fileIo.openSync(imageMedia.path, fileIo.OpenMode.READ_ONLY);
      const imgBuf = fileIo.readSync(imgFd.fd, new ArrayBuffer(fileIo.statSync(imageMedia.path).size));
      fileIo.closeSync(imgFd);
      const vidFd = fileIo.openSync(videoMedia.path, fileIo.OpenMode.READ_ONLY);
      const vidBuf = fileIo.readSync(vidFd.fd, new ArrayBuffer(videoSize));
      fileIo.closeSync(vidFd);
      const composed = await LivePhotoComposer.compose(new Uint8Array(imgBuf), new Uint8Array(vidBuf),
        options.livePhotoFormat);
      if (composed.outputBytes === null || composed.outputBytes.length === 0) {
        throw new Error('composition failed');
      }
      const outPath = cacheDir + '/' + baseName + '_live.jpg';
      const outFd = fileIo.openSync(outPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(outFd.fd, composed.outputBytes.buffer as ArrayBuffer);
      fileIo.closeSync(outFd);
      const jpegType = new MediaFileType('jpg', 'image/jpeg');
      return await MediaSaver.storeArchived(this.requireContext(), outPath, jpegType,
        baseName + '_live.jpg', folders, options, res.mediaId);
    } catch (e) {
      const imageMedia = await engine.fetch(this.requireContext(), [imageUrl], baseName + '_img_in.jpg',
        options.maxRetries, options.timeoutSeconds, () => {
        }, () => false);
      const videoMedia = await engine.fetch(this.requireContext(), [videoUrl], baseName + '_vid_in.mp4',
        options.maxRetries, options.timeoutSeconds, () => {
        }, () => false);
      const imgOut = await MediaSaver.storeArchived(this.requireContext(), imageMedia.path, imageMedia.type,
        baseName + '.jpg', folders, options, res.mediaId + '_img');
      await MediaSaver.storeArchived(this.requireContext(), videoMedia.path, videoMedia.type,
        baseName + '.mp4', folders, options, res.mediaId + '_vid');
      res.warnings = JSON.stringify([warning]);
      return imgOut;
    }
  }

  private async saveTextOutputs(task: DownloadTask, note: ResolvedNote, folders: string[],
    options: DownloadOptions): Promise<void> {
    const format: number = options.noteFormatNone ? 0 : 3;
    if (format === 0) {
      return;
    }
    const base = NoteOutput.fileName(note, this.requireSettings().get(), 0, 'txt', Date.now());
    if (format === 1 || format === 3) {
      await MediaSaver.storeText(this.requireContext(), folders, base + '.txt', NoteOutput.text(note, false));
    }
    if (format === 2 || format === 3) {
      await MediaSaver.storeText(this.requireContext(), folders, base + '.md', NoteOutput.text(note, true));
    }
  }

  private recomputeProgress(task: DownloadTask): void {
    let done = 0;
    for (const res of task.resources) {
      if (res.state === ResourceState.COMPLETED || res.state === ResourceState.SKIPPED) {
        done++;
      }
    }
    task.completedFiles = done;
    task.progress = task.resources.length > 0 ? Math.floor(done * 100 / task.resources.length) : 0;
  }

  private lastNotify = 0;
  private notifyThrottled(): void {
    const now = Date.now();
    if (now - this.lastNotify > 200) {
      this.lastNotify = now;
      this.notify();
    }
  }
}
