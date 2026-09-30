/**
 * Multi-platform downloader: parse → download media into persistent app
 * storage → register a SavedItem for the home waterfall. Progress is
 * reported through a simple listener so the parse page can show state.
 */
import { http } from '@kit.NetworkKit';
import { Context } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ParseResult, SavedItem, WorkType } from '../model/SaveModels';
import { MediaParser, NetProxy } from './PlatformServices';
import { SavedStore } from '../data/SavedStore';

export class MultiDownloadResult {
  ok: boolean = false;
  message: string = '';
  itemId: string = '';
  /** 直连被风控：建议改用网页内核提取。 */
  webFallback: boolean = false;
  sourceUrl: string = '';
}

export class MultiDownloader {
  private store: SavedStore;

  constructor(store: SavedStore) {
    this.store = store;
  }

  /** Parse + download + register. Returns user-facing message. */
  async save(context: Context, url: string, onProgress: (text: string) => void): Promise<MultiDownloadResult> {
    const out = new MultiDownloadResult();
    onProgress('解析中…');
    let parsed: ParseResult;
    try {
      parsed = await MediaParser.parse(url);
    } catch (e) {
      out.message = '解析失败：网络异常';
      return out;
    }
    if (parsed.status !== 0 || parsed.mediaItems.length === 0) {
      out.message = parsed.message.length > 0 ? parsed.message : '解析失败：没有可下载的媒体';
      out.webFallback = parsed.webFallback;
      out.sourceUrl = parsed.sourceUrl.length > 0 ? parsed.sourceUrl : url;
      return out;
    }
    return this.saveParsed(parsed, context, onProgress);
  }

  /** 已有解析结果时直接下载并入库（网页提取通道使用）。 */
  async saveParsed(parsed: ParseResult, context: Context, onProgress: (text: string) => void): Promise<MultiDownloadResult> {
    const out = new MultiDownloadResult();
    if (parsed.mediaItems.length === 0) {
      out.message = '没有可下载的媒体';
      return out;
    }
    const dir = context.filesDir + '/media';
    try {
      fileIo.mkdirSync(dir, true);
    } catch (e) {
    }
    const stamp = Date.now().toString();
    const item = new SavedItem();
    item.id = util.generateRandomUUID(true);
    item.platform = parsed.platform;
    item.workType = parsed.workType;
    item.title = parsed.title.length > 0 ? parsed.title : parsed.sourceUrl;
    if (item.title.length > 80) {
      item.title = item.title.substring(0, 80);
    }
    item.author = parsed.author;
    item.desc = parsed.title;
    item.sourceUrl = parsed.sourceUrl;
    item.createTime = Date.now();
    item.width = parsed.mediaWidth;
    item.height = parsed.mediaHeight;
    if ((item.width <= 0 || item.height <= 0) && parsed.mediaItems.length > 0) {
      item.width = parsed.mediaItems[0].width;
      item.height = parsed.mediaItems[0].height;
    }
    const seen: string[] = [];
    let index = 0;
    for (const media of parsed.mediaItems) {
      onProgress(`下载中 ${index + 1}/${parsed.mediaItems.length}`);
      const isVideo = media.type === WorkType.VIDEO;
      const ext = isVideo ? 'mp4' : 'jpg';
      const name = `${stamp}_${index}.${ext}`;
      const path = await MultiDownloader.downloadTo(media.url, dir, name);
      if (path.length === 0) {
        index++;
        continue;
      }
      // 首个带尺寸的媒体项回填 item 尺寸（瀑布流比例用）
      if ((item.width <= 0 || item.height <= 0) && media.width > 0 && media.height > 0) {
        item.width = media.width;
        item.height = media.height;
      }
      if (seen.indexOf(path) < 0) {
        seen.push(path);
        item.mediaPaths.push(path);
      }
      if (item.coverPath.length === 0 && !isVideo) {
        item.coverPath = path;
      }
      index++;
    }
    // Cover for video notes.
    if (item.coverPath.length === 0 && parsed.coverUrl.length > 0) {
      const coverName = `${stamp}_cover.jpg`;
      const coverPath = await MultiDownloader.downloadTo(parsed.coverUrl, dir, coverName);
      if (coverPath.length > 0) {
        item.coverPath = coverPath;
      }
    }
    if (item.mediaPaths.length === 0) {
      out.message = NetProxy.host.length > 0 ?
        '下载失败：所有媒体地址都不可达（代理已启用但不可用，请检查代理地址）' :
        '下载失败：所有媒体地址都不可达（海外媒体 CDN 需在设置 → 网络中配置代理并开启代理下载）';
      out.webFallback = true;
      return out;
    }
    this.store.add(item);
    out.ok = true;
    out.itemId = item.id;
    out.message = `已保存 ${item.mediaPaths.length} 个文件到应用媒体库`;
    return out;
  }

  /** 按目标 host 补 Referer：X/IG CDN 拒绝无来源下载。 */
  private static refererFor(url: string): string {
    if (url.indexOf('twimg.com') >= 0 || url.indexOf('x.com') >= 0 || url.indexOf('twitter.com') >= 0) {
      return 'https://x.com/';
    }
    if (url.indexOf('cdninstagram.com') >= 0 || url.indexOf('fbcdn.net') >= 0 ||
      url.indexOf('instagram.com') >= 0) {
      return 'https://www.instagram.com/';
    }
    if (url.indexOf('xhscdn.com') >= 0 || url.indexOf('xiaohongshu.com') >= 0) {
      return 'https://www.xiaohongshu.com/';
    }
    if (url.indexOf('tiktok') >= 0 || url.indexOf('byteoversea') >= 0 || url.indexOf('tiktokcdn') >= 0) {
      return 'https://www.tiktok.com/';
    }
    if (url.indexOf('douyin') >= 0 || url.indexOf('byteimg') >= 0) {
      return 'https://www.douyin.com/';
    }
    return '';
  }

  /** 魔数嗅探真实格式，必要时修正文件扩展名（X 图床可能回 webp）。 */
  private static fixExtension(path: string, buf: ArrayBuffer): string {
    try {
      const head = new Uint8Array(buf, 0, Math.min(16, buf.byteLength));
      let ext = '';
      if (head.length >= 3 && head[0] === 0xFF && head[1] === 0xD8 && head[2] === 0xFF) {
        ext = 'jpg';
      } else if (head.length >= 8 && head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4E &&
        head[3] === 0x47) {
        ext = 'png';
      } else if (head.length >= 12 && head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 &&
        head[3] === 0x46 && head[8] === 0x57 && head[9] === 0x45 && head[10] === 0x42 &&
        head[11] === 0x50) {
        ext = 'webp';
      } else if (head.length >= 8 && head[4] === 0x66 && head[5] === 0x74 && head[6] === 0x79 &&
        head[7] === 0x70) {
        ext = 'mp4';
      } else if (head.length >= 3 && head[0] === 0x47 && head[1] === 0x49 && head[2] === 0x46) {
        ext = 'gif';
      } else {
        return path;
      }
      const dot = path.lastIndexOf('.');
      const currentExt = dot > 0 ? path.substring(dot + 1).toLowerCase() : '';
      if (currentExt === ext || ext.length === 0) {
        return path;
      }
      const newPath = (dot > 0 ? path.substring(0, dot) : path) + '.' + ext;
      try {
        if (fileIo.accessSync(newPath)) {
          fileIo.unlinkSync(newPath);
        }
        fileIo.renameSync(path, newPath);
        return newPath;
      } catch (e) {
        return path;
      }
    } catch (e) {
      return path;
    }
  }

  private static async downloadTo(url: string, dir: string, fileName: string): Promise<string> {
    let req: http.HttpRequest | null = null;
    try {
      req = http.createHttp();
      const header: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 ' +
          '(KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1',
        'Accept': '*/*'
      };
      const referer = MultiDownloader.refererFor(url);
      if (referer.length > 0) {
        header['Referer'] = referer;
      }
      const opt: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
        // X/IG 等海外 CDN 需要代理才能下载（设置页「代理下载」开关）
        usingProxy: NetProxy.option(),
        connectTimeout: 15000,
        readTimeout: 120000
      };
      const resp = await req.request(url, opt);
      req.destroy();
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        const buf = resp.result as ArrayBuffer;
        if (buf.byteLength <= 0) {
          return '';
        }
        const path = dir + '/' + fileName;
        const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fileIo.writeSync(file.fd, buf);
        fileIo.closeSync(file.fd);
        return MultiDownloader.fixExtension(path, buf);
      }
      return '';
    } catch (e) {
      if (req !== null) {
        req.destroy();
      }
      return '';
    }
  }
}
