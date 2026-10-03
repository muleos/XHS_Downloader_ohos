/**
 * Download records — persistent store (SavedStore 同款 preferences 方案)。
 *
 * v1.19.0 根因修复：旧实现用 fileIo + JSON.parse(String(buf)) 读回文件，
 * ArkTS 中 String(ArrayBuffer) 得到 "[object ArrayBuffer]"，JSON.parse 必抛
 * → 重启后下载历史恒为空。改用 preferences（收藏库已验证同方案）。
 * Records store logical facts only: no signed URLs, no credentials, no paths.
 */
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { DownloadRecord } from '../core/models';

const STORE_NAME: string = 'download_records_store';
const KEY_ROWS: string = 'download_records';

export class RecordStore {
  private prefs: preferences.Preferences | null = null;
  private records: DownloadRecord[] = [];

  async init(context: Context): Promise<void> {
    try {
      this.prefs = preferences.getPreferencesSync(context, { name: STORE_NAME });
      const raw = this.prefs.getSync(KEY_ROWS, '[]') as string;
      const rows = JSON.parse(raw) as Array<Record<string, Object>>;
      this.records = [];
      for (const row of rows) {
        this.records.push(new DownloadRecord(
          Number(row['taskId']),
          String(row['noteId']),
          String(row['author']),
          String(row['title']),
          String(row['mediaId']),
          String(row['state']),
          Number(row['createdAt'])
        ));
      }
    } catch (e) {
      this.records = [];
    }
  }

  private persist(): void {
    if (this.prefs === null) {
      return;
    }
    try {
      const rows: Array<Record<string, Object>> = [];
      for (const r of this.records) {
        rows.push({
          'taskId': r.taskId,
          'noteId': r.noteId,
          'author': r.author,
          'title': r.title,
          'mediaId': r.mediaId,
          'state': r.state,
          'createdAt': r.createdAt
        });
      }
      this.prefs.putSync(KEY_ROWS, JSON.stringify(rows));
      this.prefs.flush();
    } catch (e) {
      // Best-effort persistence.
    }
  }

  all(): DownloadRecord[] {
    return this.records;
  }

  nextTaskId(): number {
    let max = 0;
    for (const r of this.records) {
      if (r.taskId > max) {
        max = r.taskId;
      }
    }
    return max + 1;
  }

  add(record: DownloadRecord): void {
    this.records.unshift(record);
    this.persist();
  }

  updateState(taskId: number, mediaId: string, state: string): void {
    for (const r of this.records) {
      if (r.taskId === taskId && r.mediaId === mediaId) {
        r.state = state;
      }
    }
    this.persist();
  }

  remove(taskId: number): void {
    this.records = this.records.filter((r: DownloadRecord): boolean => r.taskId !== taskId);
    this.persist();
  }

  /** 批量删除：一次删除多个任务的记录并持久化（History 批量管理用） */
  removeBatch(taskIds: number[]): void {
    const doomed: Set<number> = new Set<number>(taskIds);
    this.records = this.records.filter((r: DownloadRecord): boolean => !doomed.has(r.taskId));
    this.persist();
  }

  clear(): void {
    this.records = [];
    this.persist();
  }

  exportText(json: boolean): string {
    if (json) {
      let out = '{"version":1,"records":[';
      let first = true;
      for (const r of this.records) {
        if (!first) {
          out += ',';
        }
        out += r.toJsonText();
        first = false;
      }
      return out + ']}';
    }
    let out = 'taskId,noteId,author,title,mediaId,state,createdAt\r\n';
    for (const r of this.records) {
      out += r.toCsvRow();
    }
    return out;
  }
}
