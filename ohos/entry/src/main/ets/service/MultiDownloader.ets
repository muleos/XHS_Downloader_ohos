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
import { MediaParser } from './PlatformServices';
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
    item.sourceUrl = parsed.sourceUrl;
    item.createTime = Date.now();
    item.width = parsed.mediaWidth;
    item.height = parsed.mediaHeight;
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
      out.message = '下载失败：所有媒体地址都不可达';
      return out;
    }
    this.store.add(item);
    out.ok = true;
    out.itemId = item.id;
    out.message = `已保存 ${item.mediaPaths.length} 个文件到应用媒体库`;
    return out;
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
      const opt: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
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
        return path;
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
