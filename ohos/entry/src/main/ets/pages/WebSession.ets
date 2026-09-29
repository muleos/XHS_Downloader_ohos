import { webview } from '@kit.ArkWeb';
import { AppContainer } from '../data/AppContainer';
import { Theme, TitleBar, toast } from '../view/Common';

const XHS_HOME: string = 'https://www.xiaohongshu.com/';
const SESSION_HOST: string = 'www.xiaohongshu.com';

@Entry
@Component
struct WebSession {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Column() {
      TitleBar({ title: $r('app.string.websession_title'), showBack: true })

      Row({ space: 8 }) {
        Button($r('app.string.websession_load_home'), { buttonStyle: ButtonStyleMode.NORMAL })
          .height(36)
          .fontSize(13)
          .onClick(() => {
            this.controller.loadUrl(XHS_HOME);
          })
        Button($r('app.string.websession_extract'), { buttonStyle: ButtonStyleMode.EMPHASIZED })
          .height(36)
          .fontSize(13)
          .backgroundColor(Theme.red)
          .onClick(() => {
            this.extractSession();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12 })

      Web({ src: XHS_HOME, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .userAgent(
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36')
        .onControllerAttached(() => {
          // Attach web cookies into the session store on first sight.
        })
    }
    .padding({ left: this.leftAvoid, right: this.rightAvoid, top: this.topAvoid, bottom: this.bottomAvoid })
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }

  private extractSession(): void {
    try {
      const cookie = webview.WebCookieManager.fetchCookieSync('https://' + SESSION_HOST);
      if (cookie === undefined || cookie.length === 0) {
        toast($r('app.string.websession_extract_empty'));
        return;
      }
      AppContainer.get().client.saveManualCookie(SESSION_HOST, cookie).then(() => {
        toast($r('app.string.websession_extract_ok'));
      });
    } catch (e) {
      toast($r('app.string.websession_extract_empty'));
    }
  }
}
