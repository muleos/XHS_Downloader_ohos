/**
 * 网页内核提取兜底页：抖音等平台已把作品数据改为异步加载（并带风控），
 * 直连解析拿不到内容时，用真实浏览器内核加载页面，再从 DOM 里取直链。
 */
import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AppContainer } from '../data/AppContainer';
import { MultiDownloader } from '../service/MultiDownloader';
import { MediaParser } from '../service/PlatformServices';
import { MediaItem, ParseResult, ParseStatus, WorkType } from '../model/SaveModels';
import { Theme, toast } from '../view/Common';

const MOBILE_UA: string = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1';

const EXTRACT_JS: string = '(function(){try{var out={videos:[],images:[],title:document.title||""};' +
  'var vs=document.querySelectorAll("video");for(var i=0;i<vs.length;i++){var v=vs[i];' +
  'if(v.src){out.videos.push(v.src);}if(v.currentSrc){out.videos.push(v.currentSrc);}}' +
  'var ss=document.querySelectorAll("source");for(var j=0;j<ss.length;j++){if(ss[j].src){out.videos.push(ss[j].src);}}' +
  'var ms=document.querySelectorAll("meta");for(var k=0;k<ms.length;k++){var m=ms[k];' +
  'var p=m.getAttribute("property")||m.getAttribute("name")||"";var c=m.getAttribute("content")||"";' +
  'if((p==="og:video"||p==="og:video:url"||p==="twitter:player:stream")&&c){out.videos.push(c);}' +
  'if(p==="og:image"&&c){out.images.push(c);}if(p==="og:title"&&c){out.title=c;}}' +
  'var im=document.querySelectorAll("img");for(var n=0;n<im.length;n++){var g=im[n];' +
  'if(g.naturalWidth>=320){if(g.currentSrc){out.images.push(g.currentSrc);}else if(g.src){out.images.push(g.src);}}}' +
  'return JSON.stringify(out);}catch(e){return JSON.stringify({videos:[],images:[],title:""});}})()';

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
    } catch (e) {
      this.progress = '页面数据解析失败，可刷新页面后重试';
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
        Text('‹')
          .fontSize(28)
          .fontColor(Theme.textPrimary)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
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
          .fontColor(Theme.red)
          .onClick(() => {
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
          setTimeout(() => {
            this.extract();
          }, 2500);
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
