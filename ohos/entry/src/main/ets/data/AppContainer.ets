/** App-wide singletons (port of app/AppContainer.kt, simplified). */
import { Context } from '@kit.AbilityKit';
import { XhsHttpClient } from '../core/XhsHttpClient';
import { XhsContentRepository } from '../core/XhsContentRepository';
import { SettingsStore } from './SettingsStore';
import { RecordStore } from './RecordStore';
import { DownloadQueue } from './DownloadQueue';

export class AppContainer {
  private static inst: AppContainer | null = null;
  private ready: boolean = false;

  client: XhsHttpClient = new XhsHttpClient();
  repo: XhsContentRepository;
  settings: SettingsStore = new SettingsStore();
  records: RecordStore = new RecordStore();
  queue: DownloadQueue;

  private constructor() {
    this.repo = new XhsContentRepository(this.client);
    this.queue = new DownloadQueue(this.client);
  }

  static get(): AppContainer {
    if (AppContainer.inst === null) {
      AppContainer.inst = new AppContainer();
    }
    return AppContainer.inst;
  }

  async init(context: Context): Promise<void> {
    if (this.ready) {
      return;
    }
    await this.client.initSessionStore(context);
    await this.settings.init(context);
    await this.records.init(context);
    this.queue.init(context);
    this.ready = true;
  }
}
