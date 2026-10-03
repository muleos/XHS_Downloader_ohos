/**
 * 网页内核提取兜底页：抖音等平台已把作品数据改为异步加载（并带风控），
 * 直连解析拿不到内容时，用真实浏览器内核加载页面，再从 DOM 里取直链。
 */
import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AppContainer } from '../data/AppContainer';
import { MultiDownloader } from '../service/MultiDownloader';
import { MediaParser, InstagramService } from '../service/PlatformServices';
import { MediaItem, ParseResult, ParseStatus, WorkType } from '../model/SaveModels';
import { Theme, toast } from '../view/Common';

const MOBILE_UA: string = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1';

/**
 * 提取脚本（v1.20.0 强化）：
 *  - img 除 currentSrc/src 外解析 srcset（取最大宽度候选）——Instagram/微博
 *    等站点的 <img> 只有 srcset 没有可用 src，旧脚本因此识别不到图；
 *  - 自然宽度阈值降到 200（IG 竖图在窄视口下渲染宽度不足 320）；
 *  - og:image/og:video 恒收集（DOM 空时的最后兜底）。
 */
const EXTRACT_JS: string = '(function(){try{var out={videos:[],images:[],title:document.title||""};' +
  'function pickSrcset(el){var ss=el.getAttribute("srcset");if(!ss){return "";}' +
  'var parts=ss.split(",");var best="";var bestW=0;' +
  'for(var i=0;i<parts.length;i++){var seg=parts[i].trim().split(/\\s+/);' +
  'var u=seg[0];var w=0;if(seg[1]&&seg[1].indexOf("w")>0){w=parseInt(seg[1]);}' +
  'else{w=i;}if(u&&w>=bestW){bestW=w;best=u;}}return best;}' +
  'var vs=document.querySelectorAll("video");for(var i=0;i<vs.length;i++){var v=vs[i];' +
  'if(v.src){out.videos.push(v.src);}if(v.currentSrc){out.videos.push(v.currentSrc);}' +
  'var vp=pickSrcset(v);if(vp){out.videos.push(vp);}}' +
  'var ss=document.querySelectorAll("source");for(var j=0;j<ss.length;j++){if(ss[j].src){out.videos.push(ss[j].src);}}' +
  'var ms=document.querySelectorAll("meta");for(var k=0;k<ms.length;k++){var m=ms[k];' +
  'var p=m.getAttribute("property")||m.getAttribute("name")||"";var c=m.getAttribute("content")||"";' +
  'if((p==="og:video"||p==="og:video:url"||p==="og:video:secure_url"||p==="twitter:player:stream")&&c){out.videos.push(c);}' +
  'if(p==="og:image"&&c){out.images.push(c);}if(p==="og:title"&&c){out.title=c;}}' +
  'var im=document.querySelectorAll("img");for(var n=0;n<im.length;n++){var g=im[n];' +
  'var u2=pickSrcset(g);if(!u2&&g.currentSrc){u2=g.currentSrc;}if(!u2&&g.src){u2=g.src;}' +
  'if(!u2){continue;}' +
  'if(g.naturalWidth>=200||u2.indexOf("cdninstagram")>=0||u2.indexOf("fbcdn")>=0||u2.indexOf("scontent")>=0){' +
  'out.images.push(u2);}}' +
  'return JSON.stringify(out);}catch(e){return JSON.stringify({videos:[],images:[],title:""});}})()';

/** 触发懒加载：滚到页底再回顶（Instagram/抖音 SPA 的图片进入视口才真正加载）。 */
const SCROLL_JS: string = '(function(){try{window.scrollTo(0,document.body.scrollHeight);' +
  'setTimeout(function(){window.scrollTo(0,0);},600);}catch(e){}})()';

@Entry
@Component
struct WebExtract {
  @StorageLink('topAvoid') topAvoid: number = 0;
  @StorageLink('bottomAvoid') bottomAvoid: number = 0;
  @StorageLink('leftAvoid') leftAvoid: number = 0;
  @StorageLink('rightAvoid') rightAvoid: number = 0;
  @State url: string = '';
  @State title: string = '';
  @State videos: string[] = [];
  @State images: string[] = [];
  @State progress: string = '正在打开页面…';
  @State busy: boolean = false;
  /** 页面是 SPA 时视频元素出现较晚：自动重试提取。 */
  private attempts: number = 0;
  /** Instagram embed 解析通道只走一次（避免重复请求）。 */
  private igTried: boolean = false;
  controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    const params: Object | undefined = router.getParams();
    if (params !== undefined && params !== null) {
      const rec = params as Record<string, Object>;
      const u = rec['url'];
      if (typeof u === 'string') {
        this.url = u as string;
      }
    }
    if (this.url.length === 0) {
      this.progress = '缺少链接参数';
    }
  }

  private async extract(): Promise<void> {
    this.progress = '正在提取媒体…';
    try {
      const raw: string = await this.controller.runJavaScript(EXTRACT_JS);
      this.applyJson(raw);
    } catch (e) {
      this.progress = '提取失败，请等页面加载完成后重试';
    }
  }

  private applyJson(raw: string): void {
    try {
      const o = JSON.parse(raw) as Record<string, Object>;
      const vids: string[] = [];
      const imgs: string[] = [];
      const v = o['videos'];
      if (Array.isArray(v)) {
        for (const x of v as Array<Object>) {
          if (typeof x === 'string' && vids.indexOf(x as string) < 0) {
            vids.push(x as string);
          }
        }
      }
      const im = o['images'];
      if (Array.isArray(im)) {
        for (const x of im as Array<Object>) {
          if (typeof x === 'string' && imgs.indexOf(x as string) < 0) {
            imgs.push(x as string);
          }
        }
      }
      this.videos = vids;
      this.images = imgs;
      const t = o['title'];
      this.title = typeof t === 'string' ? t as string : '';
      this.progress = `识别到 ${vids.length} 个视频、${imgs.length} 张图片`;
      if (vids.length === 0 && imgs.length === 0) {
        // Instagram：DOM 提取不到时立即走 embed/captioned 解析通道
        // （SaveAny 同款 API；直连不通时自动带设置里的代理）
        if (InstagramService.isInstagramUrl(this.url) && !this.igTried) {
          this.igTried = true;
          this.igFallback();
        }
        // SPA 页面媒体元素出现晚：空结果时自动重试几次
        if (this.attempts < 5) {
          this.attempts++;
          this.progress = `正在等待页面渲染出媒体…（第 ${this.attempts}/5 次自动重试）`;
          // 先滚动触发懒加载，再提取
          this.controller.runJavaScript(SCROLL_JS).catch((): void => {
          });
          setTimeout(() => {
            this.extract();
          }, 2500);
        } else if (!InstagramService.isInstagramUrl(this.url)) {
          this.progress = '未识别到媒体：可下拉刷新页面后点「重新提取」';
        } else {
          this.progress = '未识别到媒体：Instagram 需登录或代理，可在「设置 → 网络与会话」配置代理后重试';
        }
      }
    } catch (e) {
      this.progress = '页面数据解析失败，可刷新页面后重试';
    }
  }

  /**
   * Instagram embed 通道兜底（v1.20.0）：GET embed/captioned 页 →
   * shortcode_media JSON → 直链列表（多图 sidecar 全量）。
   */
  private async igFallback(): Promise<void> {
    this.progress = '正在通过 Instagram 解析通道获取直链…';
    try {
      const result = await InstagramService.parse(this.url);
      if (result.status === ParseStatus.OK && result.mediaItems.length > 0) {
        const vids: string[] = [];
        const imgs: string[] = [];
        for (const m of result.mediaItems) {
          if (m.type === WorkType.VIDEO) {
            vids.push(m.url);
          } else {
            imgs.push(m.url);
          }
        }
        this.videos = vids;
        this.images = imgs;
        if (result.title.length > 0) {
          this.title = result.title;
        }
        this.attempts = 99;
        this.progress = `识别到 ${vids.length} 个视频、${imgs.length} 张图片（解析通道）`;
      } else if (this.attempts >= 5) {
        this.progress = result.message.length > 0 ? result.message : 'Instagram 解析失败，请配置代理后重试';
      }
    } catch (e) {
      if (this.attempts >= 5) {
        this.progress = 'Instagram 解析失败：网络不可达，请在「设置 → 网络与会话」配置代理';
      }
    }
  }

  private async downloadAll(): Promise<void> {
    const isVideo = this.videos.length > 0;
    const urls = isVideo ? this.videos : this.images;
    if (urls.length === 0) {
      toast('没有识别到媒体，请先等待页面加载完成');
      return;
    }
    const parsed = new ParseResult();
    parsed.platform = MediaParser.detect(this.url);
    parsed.sourceUrl = this.url;
    parsed.title = this.title.length > 0 ? this.title : this.url;
    parsed.workType = isVideo ? WorkType.VIDEO : WorkType.IMAGES;
    parsed.status = ParseStatus.OK;
    for (const u of urls) {
      const mi = new MediaItem();
      mi.url = u;
      mi.type = isVideo ? WorkType.VIDEO : WorkType.IMAGES;
      parsed.mediaItems.push(mi);
    }
    this.busy = true;
    const out = await AppContainer.get().multi.saveParsed(parsed, getContext(this), (text: string) => {
      this.progress = text;
    });
    this.busy = false;
    toast(out.message);
    if (out.ok) {
      setTimeout(() => {
        router.back();
      }, 600);
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([Theme.textPrimary])
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          router.back();
        })
        Text('网页提取')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.textPrimary)
          .layoutWeight(1)
        Text('重新提取')
          .fontSize(14)
          .fontColor(Theme.accent)
          .onClick(() => {
            this.attempts = 0;
            this.extract();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      Web({ src: this.url, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .userAgent(MOBILE_UA)
        .width('100%')
        .layoutWeight(1)
        .onPageEnd(() => {
          this.attempts = 0;
          setTimeout(() => {
            this.extract();
          }, 2000);
        })

      Column({ space: 8 }) {
        Text(this.progress)
          .fontSize(13)
          .fontColor(Theme.textSecondary)
          .maxLines(2)
          .width('100%')
        Button(this.busy ? '下载中…' : '下载全部', { buttonStyle: ButtonStyleMode.EMPHASIZED })
          .width('100%')
          .enabled(!this.busy)
          .onClick(() => {
            this.downloadAll();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: this.bottomAvoid + 12 })
      .backgroundColor(Theme.cardBg)
    }
    .padding({ left: this.leftAvoid, right: this.rightAvoid, top: this.topAvoid })
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.pageBg)
  }
}
