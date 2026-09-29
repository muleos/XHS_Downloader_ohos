/** App-wide singletons (port of app/AppContainer.kt, simplified). */
import { Context, UIAbilityContext } from '@kit.AbilityKit';
import { XhsHttpClient } from '../core/XhsHttpClient';
import { XhsContentRepository } from '../core/XhsContentRepository';
import { SettingsStore } from './SettingsStore';
import { RecordStore } from './RecordStore';
import { DownloadQueue } from './DownloadQueue';
import { WebAccountRepository } from './WebAccount';

export class AppContainer {
  private static inst: AppContainer | null = null;
  private ready: boolean = false;

  client: XhsHttpClient = new XhsHttpClient();
  repo: XhsContentRepository;
  settings: SettingsStore = new SettingsStore();
  records: RecordStore = new RecordStore();
  queue: DownloadQueue;
  webAccount: WebAccountRepository = new WebAccountRepository();
  /** Set by EntryAbility; used for the background continuous task. */
  abilityContext: UIAbilityContext | null = null;

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
    await this.webAccount.init(context);
    await this.queue.init(context, this.settings, this.records, this.repo);
    this.ready = true;
  }
}
