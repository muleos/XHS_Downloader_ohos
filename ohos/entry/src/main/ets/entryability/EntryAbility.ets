import { UIAbility, AbilityConstant, Want, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { AppContainer } from '../data/AppContainer';

const DOMAIN: number = 0x0000;
const TAG: string = 'XhsDownloader';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    AppContainer.get().init(this.context);
    // v1.19.0：启动即请求剪贴板读取权限（user_grant）。
    // 缺权限时系统会弹一次性授权框，拒绝后 getData 返回空/报错 → 一键解析
    // 一直提示「剪贴板为空」。显式申请并允许后读剪贴板才稳定。
    this.requestPasteboardPermission();
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

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
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
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }
}
