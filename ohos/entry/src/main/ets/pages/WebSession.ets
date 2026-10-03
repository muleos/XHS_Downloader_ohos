import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { AppContainer } from '../data/AppContainer';
import { XhsWebSession } from '../data/WebAccount';
import { Theme, TitleBar, toast } from '../view/Common';

const XHS_HOME: string = 'https://www.xiaohongshu.com/explore';
const SESSION_HOST: string = 'www.xiaohongshu.com';
/**
 * 电脑版 UA 登录（对齐安卓 XhsWebSession.desktopUserAgent：首段括号换桌面平台、
 * 去掉 Mobile 标识）。桌面版网页登录后 cookie 与直连解析用的桌面会话一致，
 * 且登录态更容易维持；移动版网页会跳转风控验证。
 */
const DESKTOP_UA: string =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';

/** 登录状态轮询间隔（安卓 WebViewActivity 同款 1.5s，这里取 2s 省电） */
const ACCOUNT_POLL_MS: number = 2000;

@Entry
@Component
struct WebSession {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  controller: webview.WebviewController = new webview.WebviewController();
  /** rawfile/xhs_account.js 文本（aboutToAppear 读入，安卓 WebViewScreen 同源脚本） */
  private accountJs: string = '';
  /** 登录状态轮询句柄 */
  private pollTimer: number = -1;

  aboutToAppear(): void {
    // 读取注入脚本（安卓：assets.open("xhs_account.js")）
    try {
      const buf = getContext(this).resourceManager.getRawFileContentSync('xhs_account.js');
      this.accountJs = util.TextDecoder.create('utf-8').decodeToString(buf);
    } catch (e) {
      this.accountJs = '';
    }
    // 周期轮询登录态：安卓 repeatOnLifecycle(RESUMED) 内每 1.5s evaluateJavascript 同款
    this.pollTimer = setInterval((): void => {
      this.refreshAccount();
    }, ACCOUNT_POLL_MS);
  }

  aboutToDisappear(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

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
          .backgroundColor(Theme.accent)
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
        .userAgent(DESKTOP_UA)
        .onPageEnd(() => {
          // 页面加载完成立即抓一次（安卓 onPageFinished 同款）
          this.refreshAccount();
        })
    }
    .padding({ left: this.leftAvoid, right: this.rightAvoid, top: this.topAvoid, bottom: this.bottomAvoid })
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }

  /**
   * 执行 xhs_account.js 读取登录用户并写入 WebAccountRepository
   * （安卓 refreshAccount() 移植：仅可信小红书域名，结果回传 webAccount.update）。
   */
  private refreshAccount(): void {
    if (this.accountJs.length === 0) {
      return;
    }
    let url: string = '';
    try {
      url = this.controller.getUrl();
    } catch (e) {
      return;
    }
    if (!XhsWebSession.isTrusted(url)) {
      return;
    }
    try {
      this.controller.runJavaScript(this.accountJs).then((raw: string): void => {
        if (raw === undefined || raw === null || raw.length === 0) {
          return;
        }
        AppContainer.get().webAccount.update(raw);
      }).catch((): void => {
        // 页面尚未就绪等场景，等下一轮轮询
      });
    } catch (e) {
      // controller 未附加时忽略
    }
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
