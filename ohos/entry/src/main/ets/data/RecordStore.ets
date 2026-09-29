/**
 * Download records — file-backed port of data/tasks (DownloadSessionDao subset).
 * Records store logical facts only: no signed URLs, no credentials, no paths.
 */
import { fileIo } from '@kit.CoreFileKit';
import { Context } from '@kit.AbilityKit';
import { DownloadRecord, csvCell } from '../core/models';

export class RecordStore {
  private file: string = '';
  private records: DownloadRecord[] = [];

  async init(context: Context): Promise<void> {
    this.file = context.filesDir + '/download_records.json';
    await this.reload();
  }

  private async reload(): Promise<void> {
    this.records = [];
    try {
      const stat = fileIo.statSync(this.file);
      if (stat.size <= 0) {
        return;
      }
      const file = fileIo.openSync(this.file, fileIo.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file.fd);
      const parsed: Array<Record<string, Object>> = JSON.parse(String(buf)) as Array<Record<string, Object>>;
      for (const row of parsed) {
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

  private async persist(): Promise<void> {
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
    try {
      const file = fileIo.openSync(this.file,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, JSON.stringify(rows));
      fileIo.closeSync(file.fd);
    } catch (e) {
      // Ignore write failures; records are best-effort.
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

  async add(record: DownloadRecord): Promise<void> {
    this.records.unshift(record);
    await this.persist();
  }

  async updateState(taskId: number, mediaId: string, state: string): Promise<void> {
    for (const r of this.records) {
      if (r.taskId === taskId && r.mediaId === mediaId) {
        r.state = state;
      }
    }
    await this.persist();
  }

  async remove(taskId: number): Promise<void> {
    this.records = this.records.filter((r: DownloadRecord): boolean => r.taskId !== taskId);
    await this.persist();
  }

  async clear(): Promise<void> {
    this.records = [];
    await this.persist();
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
