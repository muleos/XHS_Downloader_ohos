/** App-wide singletons (port of app/AppContainer.kt, simplified). */
import { Context, common } from '@kit.AbilityKit';
import { XhsHttpClient } from '../core/XhsHttpClient';
import { XhsContentRepository } from '../core/XhsContentRepository';
import { SettingsStore } from './SettingsStore';
import { RecordStore } from './RecordStore';
import { DownloadQueue } from './DownloadQueue';
import { WebAccountRepository } from './WebAccount';
import { SavedStore } from './SavedStore';
import { MultiDownloader } from '../service/MultiDownloader';
import { NetProxy } from '../service/PlatformServices';
import { AppSettings } from '../core/models';

export class AppContainer {
  private static inst: AppContainer | null = null;
  private ready: boolean = false;

  client: XhsHttpClient = new XhsHttpClient();
  repo: XhsContentRepository;
  settings: SettingsStore = new SettingsStore();
  records: RecordStore = new RecordStore();
  queue: DownloadQueue;
  webAccount: WebAccountRepository = new WebAccountRepository();
  saved: SavedStore = new SavedStore();
  multi: MultiDownloader;
  /** Set by EntryAbility; used for the background continuous task. */
  abilityContext: common.UIAbilityContext | null = null;

  private constructor() {
    this.repo = new XhsContentRepository(this.client);
    this.queue = new DownloadQueue(this.client);
    this.multi = new MultiDownloader(this.saved, this.records);
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
    await this.saved.init(context);
    await this.queue.init(context, this.settings, this.records, this.repo);
    // 设置页「代理/代理下载」→ 海外平台（X/IG/TikTok）解析与下载走代理
    NetProxy.apply(this.settings.get().downloadOptions.proxy,
      this.settings.get().downloadOptions.proxyDownload);
    this.syncNaming(this.settings.get());
    this.settings.onChange((s): void => {
      NetProxy.apply(s.downloadOptions.proxy, s.downloadOptions.proxyDownload);
      this.syncNaming(s);
    });
    this.ready = true;
  }

  /** 自定义命名模板同步给下载器（静态字段，避免 MultiDownloader 反向依赖容器） */
  private syncNaming(s: AppSettings): void {
    MultiDownloader.namingUseCustom = s.useCustomNamingFormat;
    MultiDownloader.namingTemplate = s.customNamingTemplate.length > 0 ?
      s.customNamingTemplate : '{postId}';
    // 「媒体与格式」下载图片/视频开关同步给多平台下载器
    MultiDownloader.imageDownload = s.downloadOptions.imageDownload;
    MultiDownloader.videoDownload = s.downloadOptions.videoDownload;
  }
}
