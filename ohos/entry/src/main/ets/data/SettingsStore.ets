/** Preferences-backed port of data/settings/AppSettings.kt. */
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { AppSettings } from '../core/models';
import { JsonNode } from '../core/JsonNode';

export class SettingsStore {
  private store: preferences.Preferences | null = null;
  private listeners: Array<(settings: AppSettings) => void> = [];
  private cached: AppSettings = new AppSettings();

  async init(context: Context): Promise<void> {
    this.store = await preferences.getPreferences(context, 'app_settings');
    const raw = this.store.getSync('json', '') as string;
    if (raw !== null && raw.length > 0) {
      const parsed = AppSettings.fromJson(JsonNode.parse(raw));
      if (parsed !== null) {
        this.cached = parsed;
      }
    }
  }

  get(): AppSettings {
    return this.cached;
  }

  async update(mutate: (s: AppSettings) => void): Promise<AppSettings> {
    mutate(this.cached);
    if (this.store !== null) {
      await this.store.put('json', JSON.stringify(this.cached.toJson()));
      await this.store.flush();
    }
    for (const listener of this.listeners) {
      listener(this.cached);
    }
    return this.cached;
  }

  onChange(listener: (settings: AppSettings) => void): void {
    this.listeners.push(listener);
  }
}
