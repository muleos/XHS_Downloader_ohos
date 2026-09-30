/**
 * Multi-platform link parsing (ported from the SaveAny reference:
 * DouyinVideoService / XMediaService / TikTokVideoService / InstagramMediaService,
 * direct channels only — the XHS pipeline stays in core/XhsNoteParser).
 */
import { http } from '@kit.NetworkKit';
import { ParseResult, ParseStatus, Platform, WorkType, MediaItem } from '../model/SaveModels';

const IOS_UA: string = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1';

/**
 * 海外平台代理桥：设置页「代理」（host:port）+「代理下载」开关 →
 * X / IG / TikTok 解析与媒体下载走该 HTTP 代理（ohos usingProxy）。
 * 小红书走国内 CDN，不经过此代理（TransferEngine 不接线）。
 * AppContainer.init 与设置变更时调用 NetProxy.apply 同步。
 */
export class NetProxy {
  static host: string = '';
  static port: number = 0;

  static apply(proxyText: string, enabled: boolean): void {
    const t = proxyText.trim();
    const m = t.match(/^(?:https?:\/\/)?([A-Za-z0-9.\-]+):(\d{2,5})\/?$/);
    if (enabled && t.length > 0 && m !== null) {
      NetProxy.host = m[1] as string;
      NetProxy.port = parseInt(m[2] as string, 10);
    } else {
      NetProxy.host = '';
      NetProxy.port = 0;
    }
  }

  /** usingProxy 取值：未启用时返回 true（跟随系统默认），启用时返回指定代理。 */
  static option(): boolean | http.HttpProxy {
    if (NetProxy.host.length > 0 && NetProxy.port > 0) {
      const proxy: http.HttpProxy = { host: NetProxy.host, port: NetProxy.port, exclusionList: [] };
      return proxy;
    }
    return true;
  }
}

interface TitleAuthor {
  title: string;
  author: string;
}

/** getFollow 的返回：正文 + 最终 URL。 */
class HttpPage {
  text: string = '';
  finalUrl: string = '';
}

class Http {
  static async getText(url: string, ua: string, referer: string, connectTimeout: number = 15000): Promise<string> {
    let req: http.HttpRequest | null = null;
    try {
      req = http.createHttp();
      const header: Record<string, string> = {
        'User-Agent': ua.length > 0 ? ua : IOS_UA,
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9'
      };
      if (referer.length > 0) {
        header['Referer'] = referer;
      }
      const opt: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        usingProxy: NetProxy.option(),
        connectTimeout: connectTimeout,
        readTimeout: 20000
      };
      const resp = await req.request(url, opt);
      req.destroy();
      if (resp.responseCode >= 200 && resp.responseCode < 400) {
        const data = resp.result as string;
        return data ? data : '';
      }
      return '';
    } catch (e) {
      if (req !== null) {
        req.destroy();
      }
      return '';
    }
  }

  /** GET，手动跟随跳转，返回正文与最终 URL（短链解析需要）。 */
  static async getFollow(url: string, ua: string, referer: string, maxHops: number): Promise<HttpPage> {
    const out = new HttpPage();
    let current: string = url;
    for (let hop = 0; hop < maxHops; hop++) {
      let req: http.HttpRequest | null = null;
      let code = 0;
      let body = '';
      let location = '';
      try {
        req = http.createHttp();
        const header: Record<string, string> = {
          'User-Agent': ua.length > 0 ? ua : IOS_UA,
          'Accept': '*/*',
          'Accept-Language': 'zh-CN,zh;q=0.9'
        };
        if (referer.length > 0) {
          header['Referer'] = referer;
        }
        const opt: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          header: header,
          expectDataType: http.HttpDataType.STRING,
          usingCache: false,
          usingProxy: NetProxy.option(),
          connectTimeout: 15000,
          readTimeout: 20000
        };
        const resp = await req.request(current, opt);
        req.destroy();
        req = null;
        code = resp.responseCode;
        body = typeof resp.result === 'string' ? (resp.result as string) : '';
        const raw: Object | undefined = resp.header;
        if (raw !== undefined && raw !== null) {
          const h = raw as Record<string, string>;
          for (const k of Object.keys(h)) {
            if (k.toLowerCase() === 'location') {
              const v = h[k];
              location = typeof v === 'string' ? v : '';
            }
          }
        }
      } catch (e) {
        if (req !== null) {
          req.destroy();
        }
        break;
      }
      if (code >= 300 && code < 400 && location.length > 0) {
        current = location.indexOf('http') === 0 ? location : Http.absolute(current, location);
        continue;
      }
      out.text = code >= 200 && code < 400 ? body : '';
      out.finalUrl = current;
      return out;
    }
    return out;
  }

  static absolute(base: string, relative: string): string {
    const m = base.match(/^https?:\/\/[^/]+/i);
    const origin = m !== null ? m[0] : '';
    if (relative.indexOf('/') === 0) {
      return origin + relative;
    }
    const slash = base.lastIndexOf('/');
    return (slash > 8 ? base.substring(0, slash + 1) : origin + '/') + relative;
  }

  static decodeHtml(text: string): string {
    return text
      .replace(/\\u002F/g, '/')
      .replace(/\\u0026/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&#x27;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&');
  }

  static num(v: Object | undefined | null): number {
    return typeof v === 'number' ? v as number : 0;
  }

  /** Balanced {..} extraction starting at `start` (string/escape aware). */
  static extractBalancedJson(text: string, start: number): string {
    let depth = 0;
    let inStr = false;
    let esc = false;
    for (let i = start; i < text.length && i < start + 3000000; i++) {
      const ch = text.charAt(i);
      if (esc) {
        esc = false;
        continue;
      }
      if (ch === '\\') {
        esc = true;
        continue;
      }
      if (ch === '"') {
        inStr = !inStr;
        continue;
      }
      if (inStr) {
        continue;
      }
      if (ch === '{') {
        depth++;
      } else if (ch === '}') {
        depth--;
        if (depth === 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    return '';
  }
}

/** 抖音（直连 _ROUTER_DATA 通道）。 */
export class DouyinService {
  static isDouyinUrl(url: string): boolean {
    return url.indexOf('douyin.com') >= 0 || url.indexOf('iesdouyin.com') >= 0;
  }

  static shareUrl(url: string): string {
    const m = url.match(/(?:iesdouyin|m\.douyin)\.com\/share\/(video|note|slides)\/(\d+)/) ||
      url.match(/douyin\.com\/(video|note|slides)\/(\d+)/);
    if (m !== null) {
      return `https://www.iesdouyin.com/share/${m[1]}/${m[2]}`;
    }
    if (url.indexOf('v.douyin.com') >= 0) {
      return url;
    }
    return url;
  }

  static postType(url: string): string {
    if (url.indexOf('/slides/') >= 0) {
      return 'slides';
    }
    if (url.indexOf('/note/') >= 0) {
      return 'note';
    }
    return 'video';
  }

  static awemeId(url: string): string {
    const m = url.match(/(?:video|note|slides)\/(\d{6,})/) ||
      url.match(/modal_id=(\d{6,})/) || url.match(/aweme_id=(\d{6,})/);
    return m !== null ? m[1] : '';
  }

  /** 页面里出现 _ROUTER_DATA 且有作品数据才返回，否则继续试下一个通道。 */
  static tryRouterData(html: string, sourceUrl: string): ParseResult | null {
    const start = html.indexOf('window._ROUTER_DATA');
    if (start < 0) {
      return null;
    }
    const brace = html.indexOf('{', start);
    if (brace < 0) {
      return null;
    }
    const jsonText = Http.extractBalancedJson(html, brace);
    if (jsonText.length === 0) {
      return null;
    }
    const r = DouyinService.mapRouterData(jsonText, sourceUrl);
    return r.status === ParseStatus.OK ? r : null;
  }

  /** 旧版 iteminfo / web detail API 返回 item_list。 */
  static fromItemList(text: string, sourceUrl: string): ParseResult | null {
    try {
      const root = JSON.parse(text) as Record<string, Object>;
      const list = Array.isArray(root['item_list']) ? root['item_list'] as Array<Object> : [];
      if (list.length === 0) {
        return null;
      }
      const result = new ParseResult();
      result.platform = Platform.DOUYIN;
      result.sourceUrl = sourceUrl;
      const built = DouyinService.buildFromAweme(list[0] as Record<string, Object>, result);
      return built.status === ParseStatus.OK ? built : null;
    } catch (e) {
      return null;
    }
  }

  /** 兜底：直接从页面源码抓 CDN 直链（抖音不再内联作品数据时的唯一办法）。 */
  static fromHtmlUrls(html: string, sourceUrl: string): ParseResult | null {
    const flat = html.replace(/\\\//g, '/');
    const result = new ParseResult();
    result.platform = Platform.DOUYIN;
    result.sourceUrl = sourceUrl;
    const videos: string[] = [];
    const images: string[] = [];
    const vids = flat.match(/https?:\/\/[^"'\s\\]+?\.(?:mp4|mov)[^"'\s\\]*/gi);
    if (vids !== null) {
      for (const u of vids) {
        if (DouyinService.isDouyinCdn(u) && videos.indexOf(u) < 0) {
          videos.push(u);
        }
      }
    }
    const imgs = flat.match(/https?:\/\/[^"'\s\\]+?(?:douyinpic|byteimg|p\d+-aio)[^"'\s\\]*?\.(?:jpeg|jpg|png|webp)[^"'\s\\]*/gi);
    if (imgs !== null) {
      for (const u of imgs) {
        if (images.indexOf(u) < 0) {
          images.push(u);
        }
      }
    }
    if (videos.length > 0) {
      const best = DouyinService.pickBestVideo(videos);
      const mi = new MediaItem();
      mi.url = best.length > 0 ? best : videos[0];
      mi.type = WorkType.VIDEO;
      result.mediaItems.push(mi);
      result.workType = WorkType.VIDEO;
    } else if (images.length > 0) {
      let count = 0;
      for (const u of images) {
        if (count >= 20) {
          break;
        }
        const mi = new MediaItem();
        mi.url = u;
        mi.type = WorkType.IMAGES;
        result.mediaItems.push(mi);
        count++;
      }
      result.workType = WorkType.IMAGES;
      result.coverUrl = images[0];
    } else {
      return null;
    }
    result.status = ParseStatus.OK;
    result.title = InstagramService.metaContent(flat, 'og:title');
    result.author = InstagramService.metaContent(flat, 'og:author');
    return result;
  }

  static isDouyinCdn(url: string): boolean {
    return url.indexOf('douyinvod') >= 0 || url.indexOf('byteimg') >= 0 ||
      url.indexOf('p3-aio') >= 0 || url.indexOf('p6-aio') >= 0 ||
      url.indexOf('p9-aio') >= 0 || url.indexOf('amemv') >= 0 ||
      url.indexOf('douyinstatic') >= 0 || url.indexOf('iesdouyin') >= 0;
  }

  /**
   * 多通道解析：短链跳转 → 分享页 _ROUTER_DATA → 官网页 → 旧 API →
   * 页面直链兜底。抖音当前把作品数据改为异步加载，直连常拿不到，
   * 全部失败时标记 webFallback，由 UI 引导使用网页内核提取。
   */
  static async parse(url: string): Promise<ParseResult> {
    const failed = DouyinService.fail(url);
    const entry = DouyinService.shareUrl(url);
    const page = await Http.getFollow(entry, IOS_UA, 'https://www.douyin.com/', 6);
    const sourceUrl = page.finalUrl.length > 0 ? page.finalUrl : (entry.length > 0 ? entry : url);
    failed.sourceUrl = sourceUrl;
    const id = DouyinService.awemeId(sourceUrl.length > 0 ? sourceUrl : url);
    if (page.text.length > 0) {
      const fromRouter = DouyinService.tryRouterData(page.text, sourceUrl);
      if (fromRouter !== null) {
        return fromRouter;
      }
      const scraped = DouyinService.fromHtmlUrls(page.text, sourceUrl);
      if (scraped !== null) {
        return scraped;
      }
    }
    if (id.length > 0) {
      const www = await Http.getFollow('https://www.douyin.com/video/' + id, IOS_UA, 'https://www.douyin.com/', 4);
      if (www.text.length > 0) {
        const r = DouyinService.tryRouterData(www.text, sourceUrl);
        if (r !== null) {
          return r;
        }
        const s = DouyinService.fromHtmlUrls(www.text, sourceUrl);
        if (s !== null) {
          return s;
        }
      }
      const itemInfo = await Http.getText('https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/?item_ids=' + id,
        IOS_UA, 'https://www.douyin.com/');
      if (itemInfo.length > 0) {
        const r = DouyinService.fromItemList(itemInfo, sourceUrl);
        if (r !== null) {
          return r;
        }
      }
      const detail = await Http.getText('https://www.douyin.com/aweme/v1/web/aweme/detail/?device_platform=webapp' +
        '&aid=6383&channel=channel_pc_web&aweme_id=' + id + '&pc_client_type=1&version_code=170400' +
        '&version_name=17.4.0&cookie_enabled=true&platform=PC&downlink=10',
      IOS_UA, 'https://www.douyin.com/');
      if (detail.length > 0) {
        const r = DouyinService.fromItemList(detail, sourceUrl);
        if (r !== null) {
          return r;
        }
      }
    }
    failed.message = '抖音直连解析失败（平台风控或需登录），可改用「网页提取」';
    failed.webFallback = true;
    return failed;
  }

  static mapRouterData(jsonText: string, sourceUrl: string): ParseResult {
    const result = new ParseResult();
    result.platform = Platform.DOUYIN;
    result.sourceUrl = sourceUrl;
    const postType = DouyinService.postType(sourceUrl);
    result.workType = postType === 'video' ? WorkType.VIDEO : WorkType.IMAGES;
    try {
      const root = JSON.parse(jsonText) as Record<string, Object>;
      const loader = root['loaderData'] as Record<string, Object>;
      let item: Record<string, Object> | null = null;
      if (loader !== null && loader !== undefined) {
        const keys = Object.keys(loader);
        for (const k of keys) {
          if (k.indexOf('/page') < 0) {
            continue;
          }
          const pageData = loader[k] as Record<string, Object>;
          const videoInfo = pageData['videoInfoRes'] as Record<string, Object>;
          const slidesInfo = pageData['slidesInfoRes'] as Record<string, Object>;
          if (videoInfo !== null && videoInfo !== undefined && Array.isArray(videoInfo['item_list'])) {
            const list = videoInfo['item_list'] as Array<Object>;
            if (list.length > 0) {
              item = list[0] as Record<string, Object>;
              break;
            }
          }
          if (slidesInfo !== null && slidesInfo !== undefined && Array.isArray(slidesInfo['aweme_details'])) {
            const list = slidesInfo['aweme_details'] as Array<Object>;
            if (list.length > 0) {
              item = list[0] as Record<string, Object>;
              break;
            }
          }
        }
      }
      if (item === null) {
        result.status = ParseStatus.PARSE_FAILED;
        result.message = '没有解析到作品数据，请确认作品仍可公开访问';
        return result;
      }
      return DouyinService.buildFromAweme(item, result);
    } catch (e) {
      result.status = ParseStatus.PARSE_FAILED;
      result.message = '没有解析到作品数据，请确认作品仍可公开访问';
      return result;
    }
  }

  static buildFromAweme(item: Record<string, Object>, result: ParseResult): ParseResult {
    if (typeof item['desc'] === 'string') {
      result.title = (item['desc'] as string).trim();
    }
    const author = item['author'] as Record<string, Object>;
    if (author !== null && author !== undefined && typeof author['nickname'] === 'string') {
      result.author = (author['nickname'] as string).trim();
    }
    const images = item['images'];
    if (Array.isArray(images)) {
      for (const img of images as Array<Object>) {
        const rec = img as Record<string, Object>;
        const urls = Array.isArray(rec['url_list']) ? rec['url_list'] as Array<Object> :
          (Array.isArray(rec['download_url_list']) ? rec['download_url_list'] as Array<Object> : []);
        for (const u of urls) {
          if (typeof u === 'string' && (u as string).indexOf('http') === 0) {
            const mi = new MediaItem();
            mi.url = u as string;
            mi.type = WorkType.IMAGES;
            mi.width = Http.num(rec['width']);
            mi.height = Http.num(rec['height']);
            result.mediaItems.push(mi);
            break;
          }
        }
      }
      if (result.mediaItems.length > 0) {
        result.workType = WorkType.IMAGES;
      }
    }
    const video = item['video'] as Record<string, Object>;
    if (video !== null && video !== undefined && result.mediaItems.length === 0) {
      result.mediaWidth = Http.num(video['width']);
      result.mediaHeight = Http.num(video['height']);
      const cover = video['cover'] as Record<string, Object>;
      if (cover !== null && cover !== undefined && Array.isArray(cover['url_list'])) {
        for (const u of cover['url_list'] as Array<Object>) {
          if (typeof u === 'string' && (u as string).indexOf('http') === 0) {
            result.coverUrl = u as string;
            break;
          }
        }
      }
      const playAddr = video['play_addr'] as Record<string, Object>;
      if (playAddr !== null && playAddr !== undefined) {
        const candidates: string[] = [];
        const uri = typeof playAddr['uri'] === 'string' ? playAddr['uri'] as string : '';
        if (uri.length > 0) {
          candidates.push('https://www.iesdouyin.com/aweme/v1/play/?line=0&video_id=' +
            encodeURIComponent(uri) + '&downgrade_264=1');
          candidates.push('https://www.iesdouyin.com/aweme/v1/play/?video_id=' + uri + '&ratio=1080p&line=0');
        }
        if (Array.isArray(playAddr['url_list'])) {
          for (const u of playAddr['url_list'] as Array<Object>) {
            if (typeof u === 'string') {
              candidates.push(u as string);
            }
          }
        }
        const best = DouyinService.pickBestVideo(candidates);
        if (best.length > 0) {
          const mi = new MediaItem();
          mi.url = best;
          mi.type = WorkType.VIDEO;
          mi.width = result.mediaWidth;
          mi.height = result.mediaHeight;
          result.mediaItems.push(mi);
          result.workType = WorkType.VIDEO;
        }
      }
    }
    if (result.mediaItems.length === 0) {
      result.status = ParseStatus.PARSE_FAILED;
      result.message = '没有解析到图文或视频内容，请确认作品公开且链接有效';
      return result;
    }
    result.status = ParseStatus.OK;
    return result;
  }

  static pickBestVideo(candidates: string[]): string {
    let best = '';
    let bestScore = -1000;
    for (const c of candidates) {
      let score = 0;
      if (c.indexOf('downgrade_264=1') >= 0) {
        score += 100;
      }
      if (c.indexOf('codec_type=0') >= 0 || /[?&]cs=0(?:&|$)/.test(c)) {
        score += 60;
      }
      if (c.indexOf('h264') >= 0) {
        score += 40;
      }
      if (c.indexOf('/aweme/v1/play') >= 0) {
        score += 10;
      }
      if (c.indexOf('playwm') >= 0) {
        score -= 20;
      }
      if (c.indexOf('douyinvod.com') >= 0) {
        score += 40;
      }
      if (c.indexOf('/video/tos/') >= 0) {
        score += 30;
      }
      if (c.indexOf('h265') >= 0 || c.indexOf('hevc') >= 0 || /[?&]cs=2(?:&|$)/.test(c)) {
        score -= 40;
      }
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  static fail(url: string): ParseResult {
    const p = new ParseResult();
    p.platform = Platform.DOUYIN;
    p.sourceUrl = url;
    p.status = ParseStatus.PARSE_FAILED;
    p.message = '没有解析到图文或视频内容，请确认作品公开且链接有效';
    return p;
  }
}

/** X（Twitter）：fxtwitter API 主通道 + og meta 兜底。 */
export class XService {
  static isXUrl(url: string): boolean {
    return url.indexOf('x.com/') >= 0 || url.indexOf('twitter.com/') >= 0 || url.indexOf('t.co/') >= 0;
  }

  static statusId(url: string): string {
    const m = url.match(/\/status(?:es)?\/(\d+)/);
    return m !== null ? m[1] : '';
  }

  static async parse(url: string): Promise<ParseResult> {
    const failed = new ParseResult();
    failed.platform = Platform.X;
    failed.sourceUrl = url;
    failed.status = ParseStatus.PARSE_FAILED;
    failed.message = '没有解析到图文或视频内容，请确认作品公开且链接有效';
    // t.co 短链：先跟到最终 x.com 地址再取 status id。
    // ohos http 默认自动跟跳（finalUrl 仍是原 t.co 地址），因此若正文里
    // 出现 x.com 目标地址，直接从 HTML 提取（国内网络 t.co 本身不可达，
    // 这里主要是配合代理环境的兜底）。
    let target = url;
    if (target.indexOf('t.co/') >= 0) {
      const page = await Http.getFollow(target, IOS_UA, '', 4);
      if (page.finalUrl.length > 0 && page.finalUrl.indexOf('t.co/') < 0) {
        target = page.finalUrl;
        failed.sourceUrl = target;
      } else if (page.text.length > 0) {
        const inner = page.text.match(/https?:\/\/(?:x|twitter)\.com\/[A-Za-z0-9_]+\/status\/(\d+)/);
        if (inner !== null) {
          target = inner[0];
          failed.sourceUrl = target;
        }
      }
    }
    const id = XService.statusId(target);
    if (id.length === 0) {
      failed.message = '不是可识别的 X 作品链接';
      return failed;
    }
    // 通道 1：fxtwitter API（Cloudflare，国内直连可达——实测主通道）
    try {
      const body = await Http.getText(`https://api.fxtwitter.com/status/${id}`, 'XHSDownloader/1.0', '', 8000);
      if (body.length > 0) {
        const mapped = XService.mapFxTwitter(body, url);
        if (mapped.status === ParseStatus.OK) {
          return mapped;
        }
      }
    } catch (e) {
      // fallthrough
    }
    // 通道 2：vxtwitter API（国内通常不可达，快速失败 6s）
    try {
      const body = await Http.getText(`https://api.vxtwitter.com/i/status/${id}`, IOS_UA, '', 6000);
      if (body.length > 0) {
        const mapped = XService.mapVxTwitter(body, url);
        if (mapped.status === ParseStatus.OK) {
          return mapped;
        }
      }
    } catch (e) {
      // fallthrough
    }
    // 通道 3（SaveAny 同款兜底）：x.com 页面 og meta + 最高码率 mp4（需代理）
    try {
      const page = await Http.getText(`https://x.com/i/status/${id}`, IOS_UA, 'https://x.com/', 6000);
      if (page.length > 0) {
        const mapped = XService.mapOgMeta(page, url);
        if (mapped.status === ParseStatus.OK) {
          return mapped;
        }
      }
    } catch (e) {
      // fallthrough
    }
    // 全部失败：fxtwitter 不可达或作品无媒体。媒体下载还需代理（twimg 被墙）。
    failed.message = 'X 解析失败：镜像通道不可达或作品无媒体。媒体下载需在「设置 → 网络」配置代理（如 127.0.0.1:7890）后开启代理下载，或改用「网页提取」';
    failed.webFallback = true;
    return failed;
  }

  /** og:title 形如「文本 (@user) on X」→ 拆出正文与作者。 */
  static splitOgTitle(rawTitle: string): TitleAuthor {
    const out: TitleAuthor = { title: rawTitle, author: '' };
    const m = rawTitle.match(/^([\s\S]*?)\s+\(@([^)]+)\)\s+on X$/);
    if (m !== null) {
      out.title = (m[1] as string).trim();
      out.author = (m[2] as string).trim();
    }
    return out;
  }

  /** bitrate 最高码率的 mp4 直链（页面嵌入的 variant 列表）。 */
  static highestBitrateVideo(html: string): string {
    const re = /bitrate:(\d+),content_type:"video\/mp4",url:"((?:\\.|[^"\\])*)"/g;
    let best = '';
    let bestBitrate = -1;
    let m: RegExpExecArray | null = re.exec(html);
    while (m !== null) {
      const bitrate = parseInt(m[1] as string);
      if (!isNaN(bitrate) && bitrate > bestBitrate) {
        bestBitrate = bitrate;
        best = m[2] as string;
      }
      m = re.exec(html);
    }
    return best;
  }

  /** x.com og meta 兜底：og:image 为 poster / 直图，variant 里挑最高码率 mp4。 */
  static mapOgMeta(html: string, sourceUrl: string): ParseResult {
    const result = new ParseResult();
    result.platform = Platform.X;
    result.sourceUrl = sourceUrl;
    const title = Http.decodeHtml(XService.metaContent(html, 'og:title'));
    const split = XService.splitOgTitle(title);
    if (split.title.length > 0) {
      result.title = split.title;
    }
    if (split.author.length > 0) {
      result.author = split.author;
    }
    const image = Http.decodeHtml(XService.metaContent(html, 'og:image'));
    const video = XService.highestBitrateVideo(html);
    if (video.length > 0) {
      const mi = new MediaItem();
      mi.type = WorkType.VIDEO;
      mi.url = video.replace(/\\\//g, '/').replace(/\\u0026/g, '&');
      if (image.length > 0) {
        mi.posterUrl = image;
      }
      result.mediaItems.push(mi);
      result.workType = WorkType.VIDEO;
      result.coverUrl = mi.posterUrl;
    } else if (image.length > 0 && image.indexOf('/photo/') < 0) {
      const mi = new MediaItem();
      mi.type = WorkType.IMAGES;
      mi.url = image;
      result.mediaItems.push(mi);
      result.workType = WorkType.IMAGES;
      result.coverUrl = mi.url;
    }
    if (result.mediaItems.length === 0) {
      result.status = ParseStatus.PARSE_FAILED;
      return result;
    }
    result.status = ParseStatus.OK;
    return result;
  }

  static metaContent(html: string, prop: string): string {
    const safe = prop.replace(':', '\\:');
    const re = new RegExp('<meta[^>]+(?:property|name)="' + safe + '"[^>]+content="([^"]*)"', 'i');
    const alt = new RegExp('<meta[^>]+content="([^"]*)"[^>]+(?:property|name)="' + safe + '"', 'i');
    const m = re.exec(html) !== null ? re.exec(html) : alt.exec(html);
    return m !== null ? m[1] : '';
  }

  /** vxtwitter 响应映射：mediaURLs 数组。 */
  static mapVxTwitter(body: string, sourceUrl: string): ParseResult {
    const result = new ParseResult();
    result.platform = Platform.X;
    result.sourceUrl = sourceUrl;
    try {
      const root = JSON.parse(body) as Record<string, Object>;
      if (typeof root['text'] === 'string') {
        result.title = root['text'] as string;
      }
      if (typeof root['user_name'] === 'string') {
        result.author = root['user_name'] as string;
      }
      const urls = root['mediaURLs'];
      if (Array.isArray(urls)) {
        for (const raw of urls as Array<Object>) {
          if (typeof raw !== 'string') {
            continue;
          }
          const u = raw as string;
          const mi = new MediaItem();
          mi.url = u;
          const isVideo = u.indexOf('.mp4') >= 0 || u.indexOf('/video/') >= 0;
          mi.type = isVideo ? WorkType.VIDEO : WorkType.IMAGES;
          result.mediaItems.push(mi);
        }
      }
      if (result.mediaItems.length === 0) {
        result.status = ParseStatus.PARSE_FAILED;
        return result;
      }
      result.workType = result.mediaItems[0].type;
      result.status = ParseStatus.OK;
      return result;
    } catch (e) {
      result.status = ParseStatus.PARSE_FAILED;
      return result;
    }
  }

  static mapFxTwitter(body: string, sourceUrl: string): ParseResult {
    const result = new ParseResult();
    result.platform = Platform.X;
    result.sourceUrl = sourceUrl;
    try {
      const root = JSON.parse(body) as Record<string, Object>;
      const tweet = root['tweet'] as Record<string, Object>;
      if (tweet === null || tweet === undefined) {
        result.status = ParseStatus.PARSE_FAILED;
        return result;
      }
      if (typeof tweet['text'] === 'string') {
        result.title = tweet['text'] as string;
      }
      const author = tweet['author'] as Record<string, Object>;
      if (author !== null && author !== undefined && typeof author['name'] === 'string') {
        result.author = author['name'] as string;
      }
      const media = tweet['media'] as Record<string, Object>;
      if (media !== null && media !== undefined) {
        if (Array.isArray(media['videos'])) {
          for (const v of media['videos'] as Array<Object>) {
            const rec = v as Record<string, Object>;
            if (typeof rec['url'] === 'string') {
              const mi = new MediaItem();
              mi.type = WorkType.VIDEO;
              mi.url = rec['url'] as string;
              if (typeof rec['thumbnail_url'] === 'string') {
                mi.posterUrl = rec['thumbnail_url'] as string;
              }
              mi.width = Http.num(rec['width']);
              mi.height = Http.num(rec['height']);
              result.mediaItems.push(mi);
              break;
            }
          }
        }
        if (Array.isArray(media['photos'])) {
          for (const p of media['photos'] as Array<Object>) {
            const rec = p as Record<string, Object>;
            if (typeof rec['url'] === 'string') {
              const mi = new MediaItem();
              mi.type = WorkType.IMAGES;
              mi.url = rec['url'] as string;
              mi.width = Http.num(rec['width']);
              mi.height = Http.num(rec['height']);
              result.mediaItems.push(mi);
            }
          }
        }
      }
      if (result.mediaItems.length === 0) {
        result.status = ParseStatus.PARSE_FAILED;
        return result;
      }
      result.workType = result.mediaItems[0].type;
      result.coverUrl = result.mediaItems[0].type === WorkType.VIDEO ?
        result.mediaItems[0].posterUrl : result.mediaItems[0].url;
      result.status = ParseStatus.OK;
      return result;
    } catch (e) {
      result.status = ParseStatus.PARSE_FAILED;
      return result;
    }
  }
}

/** TikTok：__UNIVERSAL_DATA_FOR_REHYDRATION__ / SIGI_STATE 通道。 */
export class TikTokService {
  static isTikTokUrl(url: string): boolean {
    return url.indexOf('tiktok.com') >= 0;
  }

  static videoId(url: string): string {
    const m = url.match(/\/video\/(\d+)/);
    return m !== null ? m[1] : '';
  }

  static async parse(url: string): Promise<ParseResult> {
    const failed = new ParseResult();
    failed.platform = Platform.TIKTOK;
    failed.sourceUrl = url;
    failed.status = ParseStatus.PARSE_FAILED;
    failed.message = '没有解析到图文或视频内容，请确认作品公开且链接有效';
    const id = TikTokService.videoId(url);
    const pageUrl = id.length > 0 ? `https://www.tiktok.com/@user/video/${id}` : url;
    const html = await Http.getText(pageUrl, IOS_UA, 'https://www.tiktok.com/');
    if (html.length === 0) {
      return failed;
    }
    const uni = TikTokService.scriptJson(html, '__UNIVERSAL_DATA_FOR_REHYDRATION__');
    if (uni.length > 0) {
      const mapped = TikTokService.mapUniversal(uni, url);
      if (mapped.status === ParseStatus.OK) {
        return mapped;
      }
    }
    const sigi = TikTokService.scriptJson(html, 'SIGI_STATE');
    if (sigi.length > 0) {
      const mapped2 = TikTokService.mapSigi(sigi, url, id);
      if (mapped2.status === ParseStatus.OK) {
        return mapped2;
      }
    }
    return failed;
  }

  static scriptJson(html: string, marker: string): string {
    const start = html.indexOf(`id="${marker}"`);
    if (start < 0) {
      return '';
    }
    const brace = html.indexOf('{', start);
    if (brace < 0) {
      return '';
    }
    return Http.extractBalancedJson(html, brace);
  }

  static mapUniversal(jsonText: string, sourceUrl: string): ParseResult {
    try {
      const root = JSON.parse(jsonText) as Record<string, Object>;
      const scope = root['__DEFAULT_SCOPE__'] as Record<string, Object>;
      if (scope === null || scope === undefined) {
        const empty = new ParseResult();
        empty.status = ParseStatus.PARSE_FAILED;
        return empty;
      }
      const detail = scope['webapp.video-detail'] as Record<string, Object>;
      if (detail === null || detail === undefined) {
        const empty = new ParseResult();
        empty.status = ParseStatus.PARSE_FAILED;
        return empty;
      }
      const itemInfo = detail['itemInfo'] as Record<string, Object>;
      if (itemInfo === null || itemInfo === undefined) {
        const empty = new ParseResult();
        empty.status = ParseStatus.PARSE_FAILED;
        return empty;
      }
      const item = itemInfo['itemStruct'] as Record<string, Object>;
      if (item === null || item === undefined) {
        const empty = new ParseResult();
        empty.status = ParseStatus.PARSE_FAILED;
        return empty;
      }
      return TikTokService.mapItemStruct(item, sourceUrl);
    } catch (e) {
      const empty = new ParseResult();
      empty.status = ParseStatus.PARSE_FAILED;
      return empty;
    }
  }

  static mapSigi(jsonText: string, sourceUrl: string, videoId: string): ParseResult {
    try {
      const root = JSON.parse(jsonText) as Record<string, Object>;
      const modules = root['ItemModule'] as Record<string, Object>;
      if (modules === null || modules === undefined) {
        const empty = new ParseResult();
        empty.status = ParseStatus.PARSE_FAILED;
        return empty;
      }
      const keys = Object.keys(modules);
      let chosen: Record<string, Object> | null = null;
      for (const k of keys) {
        if (videoId.length === 0 || k === videoId) {
          chosen = modules[k] as Record<string, Object>;
          break;
        }
      }
      if (chosen === null) {
        const empty = new ParseResult();
        empty.status = ParseStatus.PARSE_FAILED;
        return empty;
      }
      return TikTokService.mapItemStruct(chosen, sourceUrl);
    } catch (e) {
      const empty = new ParseResult();
      empty.status = ParseStatus.PARSE_FAILED;
      return empty;
    }
  }

  static mapItemStruct(item: Record<string, Object>, sourceUrl: string): ParseResult {
    const result = new ParseResult();
    result.platform = Platform.TIKTOK;
    result.sourceUrl = sourceUrl;
    if (typeof item['desc'] === 'string') {
      result.title = item['desc'] as string;
    }
    const author = item['author'] as Record<string, Object>;
    if (author !== null && author !== undefined && typeof author['nickname'] === 'string') {
      result.author = author['nickname'] as string;
    }
    const imagePost = item['imagePost'] as Record<string, Object>;
    if (imagePost !== null && imagePost !== undefined && Array.isArray(imagePost['images'])) {
      for (const img of imagePost['images'] as Array<Object>) {
        const rec = img as Record<string, Object>;
        const imageURL = rec['imageURL'] as Record<string, Object>;
        if (imageURL !== null && imageURL !== undefined && Array.isArray(imageURL['urlList'])) {
          for (const u of imageURL['urlList'] as Array<Object>) {
            if (typeof u === 'string' && (u as string).indexOf('http') === 0) {
              const mi = new MediaItem();
              mi.url = u as string;
              mi.type = WorkType.IMAGES;
              result.mediaItems.push(mi);
              break;
            }
          }
        }
      }
    }
    const video = item['video'] as Record<string, Object>;
    if (video !== null && video !== undefined && result.mediaItems.length === 0) {
      const playAddr = typeof video['playAddr'] === 'string' ? video['playAddr'] as string : '';
      if (playAddr.length > 0) {
        const mi = new MediaItem();
        mi.url = playAddr;
        mi.type = WorkType.VIDEO;
        result.mediaItems.push(mi);
        result.workType = WorkType.VIDEO;
      }
    }
    if (result.mediaItems.length === 0) {
      result.status = ParseStatus.PARSE_FAILED;
      result.message = '没有解析到图文或视频内容，请确认作品公开且链接有效';
      return result;
    }
    result.workType = result.mediaItems[0].type;
    result.status = ParseStatus.OK;
    return result;
  }
}

/** Instagram：embed/captioned 通道 + og meta 兜底。 */
export class InstagramService {
  static isInstagramUrl(url: string): boolean {
    return url.indexOf('instagram.com') >= 0 || url.indexOf('instagr.am') >= 0;
  }

  static shortcode(url: string): string {
    const m = url.match(/\/(p|reel|tv)\/([A-Za-z0-9_-]+)/);
    return m !== null ? m[2] : '';
  }

  static postType(url: string): string {
    const m = url.match(/\/(p|reel|tv)\/([A-Za-z0-9_-]+)/);
    return m !== null ? m[1] : 'p';
  }

  /** 从跟跳结果页 HTML 提取 shortcode：canonical 链接 / og:url / JSON 字段。 */
  static shortcodeFromHtml(html: string): string {
    const m = html.match(/instagram\.com\/(?:p|reel|tv)\/([A-Za-z0-9_-]+)/) ||
      html.match(/"shortcode"\s*:\s*"([A-Za-z0-9_-]+)"/) ||
      html.match(/"short_code"\s*:\s*"([A-Za-z0-9_-]+)"/);
    return m !== null ? m[1] : '';
  }

  static async parse(url: string): Promise<ParseResult> {
    const failed = new ParseResult();
    failed.platform = Platform.INSTAGRAM;
    failed.sourceUrl = url;
    failed.status = ParseStatus.PARSE_FAILED;
    failed.message = '不是可识别的 Instagram 作品链接';
    // /share/xxx 短链与 instagr.am 先跟到最终 /p|reel|tv/ 地址。
    // 注意 ohos http 默认自动跟跳，finalUrl 仍是原短链地址，因此
    // shortcode 还要从跟跳结果页的 HTML 里提取（canonical / og:url / JSON）。
    let target = url;
    let code = InstagramService.shortcode(target);
    if (code.length === 0) {
      const page = await Http.getFollow(target, IOS_UA, 'https://www.instagram.com/', 4);
      if (page.finalUrl.length > 0) {
        target = page.finalUrl;
        failed.sourceUrl = target;
        code = InstagramService.shortcode(target);
      }
      if (code.length === 0 && page.text.length > 0) {
        code = InstagramService.shortcodeFromHtml(page.text);
      }
    }
    if (code.length === 0) {
      return failed;
    }
    failed.message = '没有解析到 Instagram 作品媒体地址';
    const embedUrl = `https://www.instagram.com/${InstagramService.postType(target)}/${code}/embed/captioned/`;
    const html = await Http.getText(embedUrl, IOS_UA, 'https://www.instagram.com/');
    if (html.length === 0) {
      // instagram.com 在国内网络通常不可达：直连失败时给出明确指引
      failed.message = 'Instagram 无法直连（该域名在国内网络受限，或作品需登录）。可在「设置 → 网络」配置代理（如 127.0.0.1:7890）并开启「代理下载」后重试，或改用「网页提取」';
      failed.webFallback = true;
      return failed;
    }
    const start = html.indexOf('"shortcode_media"');
    if (start < 0) {
      const og = InstagramService.ogMeta(html, target);
      if (og.status !== ParseStatus.OK) {
        og.message = 'Instagram 页面未包含媒体直链（可能需登录），请开启代理后重试';
        og.webFallback = true;
      }
      return og;
    }
    const brace = html.indexOf('{', start);
    const jsonText = Http.extractBalancedJson(html, brace);
    if (jsonText.length === 0) {
      return InstagramService.ogMeta(html, target);
    }
    try {
      const media = JSON.parse(jsonText) as Record<string, Object>;
      return InstagramService.mapShortcode(media, target);
    } catch (e) {
      return InstagramService.ogMeta(html, target);
    }
  }

  /** 单节点 → 媒体项（SaveAny 同款）：视频优先（display_url 作 poster），带尺寸。 */
  static nodeToItem(node: Record<string, Object>): MediaItem | null {
    const mi = new MediaItem();
    const dims = node['dimensions'] as Record<string, Object>;
    if (dims !== null && dims !== undefined) {
      mi.width = Http.num(dims['width']);
      mi.height = Http.num(dims['height']);
    }
    const videoUrl = node['video_url'];
    if (typeof videoUrl === 'string' && (videoUrl as string).length > 0) {
      mi.type = WorkType.VIDEO;
      mi.url = videoUrl as string;
      const display = node['display_url'];
      if (typeof display === 'string') {
        mi.posterUrl = display as string;
      }
      return mi;
    }
    const display = node['display_url'];
    if (typeof display === 'string' && (display as string).length > 0) {
      mi.type = WorkType.IMAGES;
      mi.url = display as string;
      return mi;
    }
    return null;
  }

  static mapShortcode(media: Record<string, Object>, sourceUrl: string): ParseResult {
    const result = new ParseResult();
    result.platform = Platform.INSTAGRAM;
    result.sourceUrl = sourceUrl;
    const captionNode = media['edge_media_to_caption'] as Record<string, Object>;
    if (captionNode !== null && captionNode !== undefined && Array.isArray(captionNode['edges'])) {
      const edges = captionNode['edges'] as Array<Object>;
      if (edges.length > 0) {
        const node = (edges[0] as Record<string, Object>)['node'] as Record<string, Object>;
        if (node !== null && node !== undefined && typeof node['text'] === 'string') {
          result.title = node['text'] as string;
        }
      }
    }
    const owner = media['owner'] as Record<string, Object>;
    if (owner !== null && owner !== undefined && typeof owner['username'] === 'string') {
      result.author = owner['username'] as string;
    }
    const dims = media['dimensions'] as Record<string, Object>;
    if (dims !== null && dims !== undefined) {
      result.mediaWidth = Http.num(dims['width']);
      result.mediaHeight = Http.num(dims['height']);
    }
    // 多图 sidecar
    const sidecar = media['edge_sidecar_to_children'] as Record<string, Object>;
    if (sidecar !== null && sidecar !== undefined && Array.isArray(sidecar['edges'])) {
      for (const edge of sidecar['edges'] as Array<Object>) {
        const node = (edge as Record<string, Object>)['node'] as Record<string, Object>;
        if (node === null || node === undefined) {
          continue;
        }
        const mi = InstagramService.nodeToItem(node);
        if (mi !== null) {
          result.mediaItems.push(mi);
        }
      }
    }
    // 单图 / 单视频
    if (result.mediaItems.length === 0) {
      const single = InstagramService.nodeToItem(media);
      if (single !== null) {
        result.mediaItems.push(single);
      }
    }
    if (result.title.length === 0) {
      result.title = 'Instagram';
    }
    if (result.mediaItems.length === 0) {
      result.status = ParseStatus.PARSE_FAILED;
      result.message = '没有解析到 Instagram 作品媒体地址';
      return result;
    }
    result.workType = result.mediaItems[0].type;
    result.coverUrl = result.mediaItems[0].type === WorkType.VIDEO ?
      result.mediaItems[0].posterUrl : result.mediaItems[0].url;
    result.status = ParseStatus.OK;
    return result;
  }

  static ogMeta(html: string, sourceUrl: string): ParseResult {
    const result = new ParseResult();
    result.platform = Platform.INSTAGRAM;
    result.sourceUrl = sourceUrl;
    const image = InstagramService.metaContent(html, 'og:image');
    const video = InstagramService.metaContent(html, 'og:video');
    const title = InstagramService.metaContent(html, 'og:title');
    const desc = InstagramService.metaContent(html, 'og:description');
    if (title.length > 0) {
      result.title = Http.decodeHtml(title);
    } else if (desc.length > 0) {
      result.title = Http.decodeHtml(desc);
    } else {
      result.title = 'Instagram';
    }
    if (video.length > 0) {
      const mi = new MediaItem();
      mi.type = WorkType.VIDEO;
      mi.url = Http.decodeHtml(video);
      if (image.length > 0) {
        mi.posterUrl = Http.decodeHtml(image);
      }
      result.mediaItems.push(mi);
      result.workType = WorkType.VIDEO;
      result.coverUrl = mi.posterUrl;
    } else if (image.length > 0) {
      const mi = new MediaItem();
      mi.url = Http.decodeHtml(image);
      mi.type = WorkType.IMAGES;
      result.mediaItems.push(mi);
      result.workType = WorkType.IMAGES;
      result.coverUrl = mi.url;
    }
    if (result.mediaItems.length > 0) {
      result.status = ParseStatus.OK;
    }
    return result;
  }

  static metaContent(html: string, prop: string): string {
    const safe = prop.replace(':', '\\:');
    const re = new RegExp('<meta[^>]+(?:property|name)="' + safe + '"[^>]+content="([^"]*)"', 'i');
    const alt = new RegExp('<meta[^>]+content="([^"]*)"[^>]+(?:property|name)="' + safe + '"', 'i');
    const m = re.exec(html) !== null ? re.exec(html) : alt.exec(html);
    return m !== null ? m[1] : '';
  }
}

/** 平台识别 + 分发。 */
export class MediaParser {
  /**
   * 通用链接提取：任何平台（小红书 / 抖音 / Instagram / TikTok / X）均可识别。
   * 要求"域名+路径"，避免把日期、版本号之类的文本误判为链接。
   */
  static extractAnyLinks(input: string): string[] {
    const out: string[] = [];
    if (input === null || input.length === 0) {
      return out;
    }
    const regex = /(?:https?:\/\/)?(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?:\/[^\s"'<>，。；！？、【】《》\\^`{|}，]*)?/gi;
    let match: RegExpExecArray | null = regex.exec(input);
    while (match !== null) {
      const start = match.index;
      const raw0 = match[0];
      const preceding = start > 0 ? input[start - 1] : '';
      const isWordish = (preceding >= 'a' && preceding <= 'z') ||
        (preceding >= 'A' && preceding <= 'Z') || (preceding >= '0' && preceding <= '9') ||
        preceding === '.' || preceding === '_' || preceding === '-';
      if (!isWordish) {
        let end = raw0.length;
        const junk = ')]}.,;!，。）】';
        while (end > 0 && junk.indexOf(raw0[end - 1]) >= 0) {
          end--;
        }
        const link = raw0.substring(0, end);
        // 必须带路径（分享链接都有），排除 "xiaohongshu.com" 之类裸域名
        if (link.indexOf('/') >= 0) {
          out.push(link);
        }
      }
      match = regex.exec(input);
    }
    return out;
  }

  /** 取首个可识别平台的链接（自动跳过无关文本）。 */
  static firstSupportedLink(input: string): string {
    const links = MediaParser.extractAnyLinks(input);
    for (const link of links) {
      if (MediaParser.detect(link) !== Platform.UNKNOWN) {
        return link;
      }
    }
    return links.length > 0 ? links[0] : '';
  }

  static detect(url: string): Platform {
    if (url.indexOf('xiaohongshu.com') >= 0 || url.indexOf('xhslink.com') >= 0 || url.indexOf('xhslink.cn') >= 0) {
      return Platform.XHS;
    }
    if (DouyinService.isDouyinUrl(url)) {
      return Platform.DOUYIN;
    }
    if (InstagramService.isInstagramUrl(url)) {
      return Platform.INSTAGRAM;
    }
    if (TikTokService.isTikTokUrl(url)) {
      return Platform.TIKTOK;
    }
    if (XService.isXUrl(url)) {
      return Platform.X;
    }
    return Platform.UNKNOWN;
  }

  static async parse(url: string): Promise<ParseResult> {
    const platform = MediaParser.detect(url);
    switch (platform) {
      case Platform.DOUYIN:
        return DouyinService.parse(url);
      case Platform.INSTAGRAM:
        return InstagramService.parse(url);
      case Platform.TIKTOK:
        return TikTokService.parse(url);
      case Platform.X:
        return XService.parse(url);
      default: {
        const failed = new ParseResult();
        failed.sourceUrl = url;
        failed.status = ParseStatus.PARSE_FAILED;
        failed.message = '无法识别链接平台';
        return failed;
      }
    }
  }
}
