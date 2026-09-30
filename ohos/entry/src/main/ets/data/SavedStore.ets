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
