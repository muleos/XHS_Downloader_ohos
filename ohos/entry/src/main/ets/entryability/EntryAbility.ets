import { UIAbility, AbilityConstant, Want, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { AppContainer } from '../data/AppContainer';
import { MediaParser } from '../service/PlatformServices';

const DOMAIN: number = 0x0000;
const TAG: string = 'XhsDownloader';

export default class EntryAbility extends UIAbility {
  /** 冷启动时暂存的分享文本（onWindowStageCreate 页面就绪后再分发）。 */
  private pendingShare: string = '';
  /** loadContent 完成后置 true（此后分享可直接分发）。 */
  private windowReady: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    AppContainer.get().init(this.context);
    // v1.19.0：启动即请求剪贴板读取权限（user_grant）。
    // 缺权限时系统会弹一次性授权框，拒绝后 getData 返回空/报错 → 一键解析
    // 一直提示「剪贴板为空」。显式申请并允许后读剪贴板才稳定。
    this.requestPasteboardPermission();
    // v1.23.3：系统分享 / 浏览器链接接入（小红书/抖音/IG/X/TikTok 等）
    this.handleWant(want);
  }

  private requestPasteboardPermission(): void {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const perms: Array<Permissions> = ['ohos.permission.READ_PASTEBOARD'];
      atManager.requestPermissionsFromUser(this.context, perms).then((result) => {
        hilog.info(DOMAIN, TAG, 'pasteboard perm results: %{public}s', JSON.stringify(result.authResults));
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'pasteboard perm err: %{public}s', JSON.stringify(err));
      });
    } catch (e) {
      // 忽略：解析圆钮读取失败时仍会给用户明确提示
    }
  }

  /**
   * 分享 Want 统一入口（v1.23.3）：
   *  - want.uri 为 http(s) 链接（viewData 浏览器通道）→ 直接分发；
   *  - ohos.want.action.sendData（系统分享面板）→ ShareKit getSharedData
   *    （Promise）逐条记录取 content（纯文本）→ uri（URI 记录）。
   */
  private handleWant(want: Want): void {
    const uri = want.uri !== undefined && want.uri !== null ? want.uri : '';
    if (uri.indexOf('http') === 0) {
      this.pendingShare = uri;
      this.dispatchIfReady();
      return;
    }
    try {
      systemShare.getSharedData(want).then((data: systemShare.SharedData): void => {
        const text = this.pickSharedText(data);
        if (text.length > 0) {
          this.pendingShare = text;
          this.dispatchIfReady();
        }
      }).catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'getSharedData err: %{public}s', JSON.stringify(err));
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'handleWant err: %{public}s', String(e));
    }
  }

  /** 从分享记录提取文本：content（纯文本，优先含支持链接的）→ uri（URI 记录）。 */
  private pickSharedText(data: systemShare.SharedData): string {
    try {
      const records = data.getRecords();
      let fallback = '';
      for (const rec of records) {
        const content = rec.content !== undefined && rec.content !== null ? rec.content : '';
        if (content.length > 0) {
          if (MediaParser.firstSupportedLink(content).length > 0) {
            return content;
          }
          if (fallback.length === 0) {
            fallback = content;
          }
        }
        if (rec.uri !== undefined && rec.uri !== null) {
          const u = rec.uri.toString();
          if (u.indexOf('http') === 0) {
            return u;
          }
          if (fallback.length === 0 && u.length > 0) {
            fallback = u;
          }
        }
      }
      return fallback;
    } catch (e) {
      return '';
    }
  }

  /** 分享文本 → 解析页：先切到解析 Tab，再写入 parseRequest 触发解析。 */
  private dispatchParse(text: string): void {
    if (text.length === 0) {
      return;
    }
    AppStorage.setOrCreate<string>('parseRequest', text);
    AppStorage.setOrCreate<number>('tabRequest', 1);
  }

  /** 冷启动时页面尚未就绪：onWindowStageCreate 载入完成后由 pendingShare 分发。 */
  private dispatchIfReady(): void {
    if (this.windowReady) {
      const text = this.pendingShare;
      this.pendingShare = '';
      setTimeout(() => {
        this.dispatchParse(text);
      }, 50);
    }
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      const mainWin = windowStage.getMainWindowSync();
      // Immersive status bar like the Android version.
      mainWin.setWindowLayoutFullScreen(true);
      const sys = mainWin.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const nav = mainWin.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      // Avoid-area rects are in px; convert to vp so page paddings are physical.
      const ui = mainWin.getUIContext();
      const topVp = Math.ceil(ui.px2vp(sys.topRect.height));
      // Bottom: gesture indicator / nav bar, normalized to at most 28vp.
      const bottomRaw = Math.max(nav.bottomRect.height, sys.bottomRect.height);
      const bottomVp = Math.min(Math.ceil(ui.px2vp(bottomRaw)), 28);
      const leftVp = Math.ceil(ui.px2vp(Math.max(sys.leftRect.width, 0)));
      const rightVp = Math.ceil(ui.px2vp(Math.max(sys.rightRect.width, 0)));
      AppStorage.setOrCreate('topAvoid', topVp);
      AppStorage.setOrCreate('bottomAvoid', bottomVp);
      AppStorage.setOrCreate('leftAvoid', leftVp);
      AppStorage.setOrCreate('rightAvoid', rightVp);
      mainWin.setWindowSystemBarProperties({
        statusBarContentColor: '#000000'
      });
      // 「保持屏幕常亮」设置启动时生效（设置页切换时即时应用）
      try {
        mainWin.setWindowKeepScreenOn(AppContainer.get().settings.get().keepScreenOn);
      } catch (e) {
      }
      // 冷启动分享：页面就绪后分发 pendingShare（含 onCreate 期间 getSharedData 异步返回的）
      this.windowReady = true;
      if (this.pendingShare.length > 0) {
        this.dispatchIfReady();
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  /** 热启动（应用已在后台）：直接分发分享文本。 */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onNewWant');
    this.handleWant(want);
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }
}
