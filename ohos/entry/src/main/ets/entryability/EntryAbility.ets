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
      AppStorage.setOrCreate('topAvoid', sys.topRect.height);
      AppStorage.setOrCreate('bottomAvoid', Math.max(nav.bottomRect.height, sys.bottomRect.height));
      AppStorage.setOrCreate('leftAvoid', Math.max(sys.leftRect.width, 0));
      AppStorage.setOrCreate('rightAvoid', Math.max(sys.rightRect.width, 0));
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
