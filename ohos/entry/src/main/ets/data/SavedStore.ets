/**
 * Persisted store of downloaded media shown on the waterfall home feed.
 * Media files live under <filesDir>/media so they survive cache cleanup.
 */
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { SavedItem } from '../model/SaveModels';

const STORE_NAME = 'saved_media_store';
const KEY_ITEMS = 'saved_items';
const MEDIA_DIR = 'media';

export class SavedStore {
  private prefs: preferences.Preferences | null = null;
  private items: SavedItem[] = [];

  async init(context: Context): Promise<void> {
    try {
      this.prefs = preferences.getPreferencesSync(context, { name: STORE_NAME });
      const raw = this.prefs.getSync(KEY_ITEMS, '[]') as string;
      const arr = JSON.parse(raw) as Array<Object>;
      const loaded: SavedItem[] = [];
      for (const v of arr) {
        if (typeof v === 'string') {
          const item = SavedItem.fromJSON(v as string);
          if (item !== null) {
            loaded.push(item);
          }
        }
      }
      // Drop entries whose files are gone (cache/file cleanup).
      this.items = [];
      for (const it of loaded) {
        if (it.mediaPaths.length > 0 && fileIo.accessSync(it.mediaPaths[0])) {
          this.items.push(it);
        }
      }
    } catch (e) {
      this.items = [];
    }
  }

  getAll(): SavedItem[] {
    return this.items;
  }

  /**
   * 收藏页同款去重：按源链接保留最新一次保存（重复解析同一作品不重复计数）。
   * 统计页与收藏页共用本方法，保证两边数量一致。
   */
  dedupeBySource(items: SavedItem[]): SavedItem[] {
    const seen: Record<string, number> = {};
    const deduped: SavedItem[] = [];
    for (const it of items) {
      const key = it.sourceUrl.length > 0 ? it.sourceUrl : it.id;
      const prev = seen[key];
      if (prev === undefined) {
        seen[key] = deduped.length;
        deduped.push(it);
      } else if (it.createTime > deduped[prev].createTime) {
        deduped[prev] = it;
      }
    }
    return deduped;
  }

  byId(id: string): SavedItem | null {
    for (const it of this.items) {
      if (it.id === id) {
        return it;
      }
    }
    return null;
  }

  /** Newest first. */
  add(item: SavedItem): void {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].id === item.id) {
        this.items.splice(i, 1);
        break;
      }
    }
    this.items.unshift(item);
    this.persist();
    AppStorage.setOrCreate('savedVersion', Date.now());
  }

  remove(id: string): void {
    const next: SavedItem[] = [];
    for (const it of this.items) {
      if (it.id !== id) {
        next.push(it);
      }
    }
    this.items = next;
    this.persist();
    AppStorage.setOrCreate('savedVersion', Date.now());
  }

  /** 批量删除（收藏页批量管理）：一次 persist + 一次 savedVersion 通知。 */
  removeBatch(ids: string[]): void {
    if (ids.length === 0) {
      return;
    }
    const doomed: Set<string> = new Set<string>(ids);
    const next: SavedItem[] = [];
    for (const it of this.items) {
      if (!doomed.has(it.id)) {
        next.push(it);
      }
    }
    this.items = next;
    this.persist();
    AppStorage.setOrCreate('savedVersion', Date.now());
  }

  private persist(): void {
    if (this.prefs === null) {
      return;
    }
    try {
      const parts: string[] = [];
      for (const it of this.items) {
        parts.push(it.toJSON());
      }
      this.prefs.putSync(KEY_ITEMS, JSON.stringify(parts));
      this.prefs.flush();
    } catch (e) {
      // Best-effort persistence.
    }
  }
}
