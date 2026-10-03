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
import { RecordStore } from '../data/RecordStore';
import { DownloadRecord } from '../core/models';

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
  /** 下载记录 store（v1.19.0：多平台下载也写历史，此前只有小红书队列写） */
  private records: RecordStore | null = null;
  /** 自定义命名（安卓 NamingFormat 移植；由 AppContainer 从设置同步，避免循环依赖） */
  static namingUseCustom: boolean = false;
  static namingTemplate: string = '{postId}';
  /** 「媒体与格式」下载开关（设置页同步）：关闭后跳过对应类型的媒体 */
  static imageDownload: boolean = true;
  static videoDownload: boolean = true;

  constructor(store: SavedStore, records: RecordStore | null = null) {
    this.store = store;
    this.records = records;
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

  /**
   * 已有解析结果时直接下载并入库（网页提取通道 / 队列多平台任务使用）。
   * onStep（可选）：每完成一个媒体回调 (done, total)，返回 false 中止下载
   * （下载任务列表的取消/暂停依赖此钩子）；中止时已下载文件仍会入库。
   */
  async saveParsed(parsed: ParseResult, context: Context, onProgress: (text: string) => void,
    onStep?: (done: number, total: number) => boolean): Promise<MultiDownloadResult> {
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
    // 预统计需下载条数（关闭的媒体类型不计入进度分母）
    let eligible = 0;
    for (const media of parsed.mediaItems) {
      if (media.type === WorkType.VIDEO && !MultiDownloader.videoDownload) {
        continue;
      }
      if (media.type !== WorkType.VIDEO && !MultiDownloader.imageDownload) {
        continue;
      }
      eligible++;
    }
    const seen: string[] = [];
    let done = 0;
    let aborted = false;
    for (const media of parsed.mediaItems) {
      // 「媒体与格式」开关：关闭图片/视频下载时跳过对应类型（设置仅用于新任务）
      if (media.type === WorkType.VIDEO && !MultiDownloader.videoDownload) {
        continue;
      }
      if (media.type !== WorkType.VIDEO && !MultiDownloader.imageDownload) {
        continue;
      }
      // 队列任务取消/暂停钩子：返回 false 时中止（已下载文件保留入库）
      if (onStep !== undefined && !onStep(done, eligible)) {
        aborted = true;
        break;
      }
      onProgress(`下载中 ${done + 1}/${eligible}`);
      const isVideo = media.type === WorkType.VIDEO;
      const ext = isVideo ? 'mp4' : 'jpg';
      const name = MultiDownloader.buildFileName(item, done, ext);
      const path = await MultiDownloader.downloadTo(media.url, dir, name);
      if (path.length === 0) {
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
      done++;
    }
    // 任务被取消/暂停：已下载的文件仍入库，返回取消语义
    if (aborted) {
      if (item.mediaPaths.length > 0) {
        this.store.add(item);
        out.ok = true;
        out.itemId = item.id;
        out.message = `已取消下载，已保存 ${item.mediaPaths.length} 个文件到应用媒体库`;
      } else {
        out.message = '已取消下载';
      }
      return out;
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
    // 下载历史持久化记录（与小红书队列同格式；taskId 用记录 store 自增 id）
    if (this.records !== null) {
      const recId = this.records.nextTaskId();
      this.records.add(new DownloadRecord(recId, MultiDownloader.extractPostId(item.sourceUrl, item.id),
        item.author, item.title, '', 'downloaded', Date.now()));
    }
    out.ok = true;
    out.itemId = item.id;
    out.message = `已保存 ${item.mediaPaths.length} 个文件到应用媒体库`;
    return out;
  }

  /**
   * 自定义命名模板（安卓 NoteOutput.fileName 一比一）：
   * {username}{userId}{title}{postId}{publishTime}{index}{index_padded}{downloadTimestamp}，
   * 未开启自定义时用 {postId}；恒追加 _NN 序号后缀防冲突。
   */
  private static buildFileName(item: SavedItem, index: number, ext: string): string {
    const seq = String(index + 1);
    const postId = MultiDownloader.extractPostId(item.sourceUrl, item.id);
    const publishTime = MultiDownloader.formatTime(item.createTime);
    const values: Record<string, string> = {
      'username': item.author,
      'userId': '',
      'title': item.title,
      'postId': postId,
      'publishTime': publishTime,
      'index': seq,
      'index_padded': seq.padStart(2, '0'),
      'downloadTimestamp': String(item.createTime)
    };
    const template = MultiDownloader.namingUseCustom ? MultiDownloader.namingTemplate : '{postId}';
    let base = template.replace(/\{([a-zA-Z_]+)\}/g, (m0: string, key: string): string => {
      const v = values[key];
      return v === undefined ? m0 : v;
    });
    // 记录时间/序号兜底：模板全部命中为空时退回时间戳，保证文件名非空
    if (base.replace(/[^A-Za-z0-9\u4e00-\u9fa5]/g, '').length === 0) {
      base = String(item.createTime);
    }
    return MultiDownloader.safePart(base, postId) + '_' + seq.padStart(2, '0') + '.' + ext;
  }

  /** 文件名安全化（安卓 safePart 移植）：非法字符替换、去首尾点、UTF-8 160 字节截断。 */
  private static safePart(value: string, fallback: string): string {
    const clean = value.replace(/[\u0000-\u001f\\/:*?"<>|]/g, '_').trim().replace(/^\.+|\.+$/g, '');
    let out = '';
    for (const ch of clean) {
      if (out.length + ch.length > 150) {
        break;
      }
      out += ch;
    }
    return out.length > 0 ? out : fallback;
  }

  /** 从分享链接提取作品 ID：xhs explore 24 位 hex / 通用末段路径；短链取不到时退回 item.id。 */
  private static extractPostId(url: string, fallback: string): string {
    const m = url.match(/(?:explore|discovery\/item|status|note|p|reel|tv)\/([0-9A-Za-z_-]+)/);
    if (m !== null) {
      return m[1] as string;
    }
    const hex = url.match(/[0-9a-fA-F]{24}/);
    if (hex !== null) {
      return hex[0];
    }
    return fallback;
  }

  /** createTime → yyyy-MM-dd_HH-mm-ss（publishTime 占位用） */
  private static formatTime(ms: number): string {
    const d = new Date(ms);
    const p = (n: number): string => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}_${p(d.getHours())}-` +
      `${p(d.getMinutes())}-${p(d.getSeconds())}`;
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
