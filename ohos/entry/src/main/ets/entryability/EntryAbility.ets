import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppContainer } from '../data/AppContainer';

const DOMAIN: number = 0x0000;
const TAG: string = 'XhsDownloader';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    AppContainer.get().init(this.context);
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
