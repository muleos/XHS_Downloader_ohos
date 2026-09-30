/**
 * Durable task store — JSON-file parity of data/tasks (RoomTaskRepository subset).
 * Tasks + sessions + resources persist across process restarts with the same
 * status vocabulary as the Android app.
 */
import { fileIo } from '@kit.CoreFileKit';
import { Context } from '@kit.AbilityKit';
import { DownloadOptions, ResolvedNote } from '../core/models';

export enum TaskStatus {
  QUEUED = 'QUEUED',
  RESOLVING = 'RESOLVING',
  DOWNLOADING = 'DOWNLOADING',
  WAITING_FOR_USER = 'WAITING_FOR_USER',
  PAUSED = 'PAUSED',
  CANCELLED = 'CANCELLED',
  COMPLETED = 'COMPLETED',
  PARTIAL = 'PARTIAL',
  FAILED = 'FAILED',
  SKIPPED = 'SKIPPED'
}

export enum ResourceState {
  DOWNLOADING = 'DOWNLOADING',
  COMPLETED = 'COMPLETED',
  SKIPPED = 'SKIPPED',
  FAILED = 'FAILED'
}

export class TaskResource {
  mediaId: string = '';
  name: string = '';
  ext: string = '';
  state: ResourceState = ResourceState.DOWNLOADING;
  bytes: number = 0;
  refsJson: string = '[]';
  warnings: string = '[]';
  livePair: boolean = false;
  recordKey: string = '';
  claimed: boolean = false;
  tempPath: string = '';
  savedUri: string = '';
}

export class TaskSession {
  rawInput: string = '';
  options: DownloadOptions | null = null;
  resolvedJson: string = '';
  selected: number[] = [];
  requireSelection: boolean = false;
  infoOnly: boolean = false;
  remark: string = '';
}

export class DownloadTask {
  id: number = 0;
  noteUrl: string = '';
  noteTitle: string = '';
  noteType: string = 'normal';
  status: TaskStatus = TaskStatus.QUEUED;
  totalFiles: number = 0;
  completedFiles: number = 0;
  createdAt: number = 0;
  updatedAt: number = 0;
  errorMessage: string = '';
  session: TaskSession = new TaskSession();
  resources: TaskResource[] = [];
  progress: number = 0;
  active: boolean = false;
}

interface TaskPersistPayload {
  tasks: DownloadTask[];
  nextId: number;
  authors: Record<string, string>;
  completedKeys: string[];
}

export class TaskStore {
  private file: string = '';
  private tasks: DownloadTask[] = [];
  private nextId: number = 1;
  private completedKeys: Set<string> = new Set<string>();
  private authors: Record<string, string> = {};

  async init(context: Context): Promise<void> {
    this.file = context.filesDir + '/download_tasks.json';
    try {
      const stat = fileIo.statSync(this.file);
      const f = fileIo.openSync(this.file, fileIo.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(f.fd, buf);
      fileIo.closeSync(f.fd);
      const raw = JSON.parse(String(buf)) as Record<string, Object>;
      this.tasks = (raw['tasks'] as DownloadTask[]) ?? [];
      this.nextId = Number(raw['nextId'] ?? this.tasks.length + 1);
      this.authors = (raw['authors'] as Record<string, string>) ?? {};
      const keys = (raw['completedKeys'] as string[]) ?? [];
      this.completedKeys = new Set<string>(keys);
      for (const task of this.tasks) {
        if (task.status === TaskStatus.DOWNLOADING || task.status === TaskStatus.RESOLVING) {
          task.status = TaskStatus.PAUSED;
          task.active = false;
        }
      }
    } catch (e) {
      this.tasks = [];
    }
  }

  private persist(): void {
    try {
      const payload: TaskPersistPayload = {
        'tasks': this.tasks,
        'nextId': this.nextId,
        'authors': this.authors,
        'completedKeys': Array.from(this.completedKeys)
      };
      const tmp = this.file + '.tmp';
      const f = fileIo.openSync(tmp, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, JSON.stringify(payload));
      fileIo.closeSync(f.fd);
      fileIo.renameSync(tmp, this.file);
    } catch (e) {
    }
  }

  all(): DownloadTask[] {
    return this.tasks;
  }

  byId(id: number): DownloadTask | null {
    for (const task of this.tasks) {
      if (task.id === id) {
        return task;
      }
    }
    return null;
  }

  create(url: string): DownloadTask {
    const task = new DownloadTask();
    task.id = this.nextId++;
    task.noteUrl = url;
    task.createdAt = Date.now();
    task.updatedAt = Date.now();
    this.tasks.unshift(task);
    this.persist();
    return task;
  }

  touch(task: DownloadTask): void {
    task.updatedAt = Date.now();
    this.persist();
  }

  markCompletedKey(key: string): void {
    this.completedKeys.add(key);
    this.persist();
  }

  hasCompletedKey(key: string): boolean {
    return this.completedKeys.has(key);
  }

  remark(authorId: string): string {
    return this.authors[authorId] !== undefined ? this.authors[authorId] : '';
  }

  setRemark(authorId: string, remark: string): void {
    if (authorId.length === 0) {
      return;
    }
    if (remark.length === 0) {
      const next: Record<string, string> = {};
      for (const key of Object.keys(this.authors)) {
        if (key !== authorId) {
          next[key] = this.authors[key];
        }
      }
      this.authors = next;
    } else {
      this.authors[authorId] = remark;
    }
    this.persist();
  }

  remove(id: number): void {
    this.tasks = this.tasks.filter((t: DownloadTask): boolean => t.id !== id);
    this.persist();
  }

  clearFinished(): void {
    this.tasks = this.tasks.filter((t: DownloadTask): boolean =>
      t.status !== TaskStatus.COMPLETED && t.status !== TaskStatus.CANCELLED &&
      t.status !== TaskStatus.FAILED && t.status !== TaskStatus.SKIPPED);
    this.persist();
  }

  storeNote(taskId: number, note: ResolvedNote): void {
    const task = this.byId(taskId);
    if (task !== null) {
      task.session.resolvedJson = JSON.stringify(note.toBundle());
      this.touch(task);
    }
  }

  loadNote(task: DownloadTask): ResolvedNote | null {
    if (task.session.resolvedJson.length === 0) {
      return null;
    }
    try {
      return ResolvedNote.fromBundle(JSON.parse(task.session.resolvedJson) as Record<string, Object>);
    } catch (e) {
      return null;
    }
  }
}
