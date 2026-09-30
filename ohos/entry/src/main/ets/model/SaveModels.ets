/**
 * Multi-platform media models (ported from SaveAny reference implementation
 * model/saveany/Models, trimmed to what this app needs). ArkTS-strict.
 */

export enum Platform {
  XHS = 0,
  DOUYIN = 1,
  INSTAGRAM = 2,
  TIKTOK = 3,
  X = 4,
  UNKNOWN = 5
}

export enum WorkType {
  IMAGES = 0,
  VIDEO = 1
}

export enum ParseStatus {
  OK = 0,
  PARSE_FAILED = 1
}

export class MediaItem {
  url: string = '';
  type: WorkType = WorkType.IMAGES;
  width: number = 0;
  height: number = 0;
  posterUrl: string = '';
}

export class ParseResult {
  platform: Platform = Platform.UNKNOWN;
  status: ParseStatus = ParseStatus.PARSE_FAILED;
  sourceUrl: string = '';
  noteId: string = '';
  title: string = '';
  author: string = '';
  workType: WorkType = WorkType.IMAGES;
  mediaWidth: number = 0;
  mediaHeight: number = 0;
  coverUrl: string = '';
  audioUrl: string = '';
  shareText: string = '';
  message: string = '';
  /** 直连通道被平台风控挡住时置 true，UI 提示改用网页内核提取。 */
  webFallback: boolean = false;
  mediaItems: MediaItem[] = [];
}

export class SavedItem {
  id: string = '';
  platform: Platform = Platform.UNKNOWN;
  workType: WorkType = WorkType.IMAGES;
  title: string = '';
  /** 原帖文本内容（正文；查看器底部展示） */
  desc: string = '';
  author: string = '';
  sourceUrl: string = '';
  createTime: number = 0;
  coverPath: string = '';
  mediaPaths: string[] = [];
  width: number = 0;
  height: number = 0;

  hasMedia(): boolean {
    return this.mediaPaths.length > 0;
  }

  coverOrFirst(): string {
    if (this.coverPath.length > 0) {
      return this.coverPath;
    }
    return this.mediaPaths.length > 0 ? this.mediaPaths[0] : '';
  }

  toJSON(): string {
    const payload: Record<string, Object> = {
      'id': this.id,
      'platform': this.platform as Object,
      'workType': this.workType as Object,
      'title': this.title,
      'desc': this.desc,
      'author': this.author,
      'sourceUrl': this.sourceUrl,
      'createTime': this.createTime as Object,
      'coverPath': this.coverPath,
      'mediaPaths': this.mediaPaths as Object,
      'width': this.width as Object,
      'height': this.height as Object
    };
    return JSON.stringify(payload);
  }

  static fromJSON(text: string): SavedItem | null {
    try {
      const o = JSON.parse(text) as Record<string, Object>;
      const item = new SavedItem();
      item.id = typeof o['id'] === 'string' ? o['id'] as string : '';
      item.platform = typeof o['platform'] === 'number' ? o['platform'] as Platform : Platform.UNKNOWN;
      item.workType = typeof o['workType'] === 'number' ? o['workType'] as WorkType : WorkType.IMAGES;
      item.title = typeof o['title'] === 'string' ? o['title'] as string : '';
      item.desc = typeof o['desc'] === 'string' ? o['desc'] as string : '';
      item.author = typeof o['author'] === 'string' ? o['author'] as string : '';
      item.sourceUrl = typeof o['sourceUrl'] === 'string' ? o['sourceUrl'] as string : '';
      item.createTime = typeof o['createTime'] === 'number' ? o['createTime'] as number : 0;
      item.coverPath = typeof o['coverPath'] === 'string' ? o['coverPath'] as string : '';
      if (Array.isArray(o['mediaPaths'])) {
        for (const p of o['mediaPaths'] as Array<Object>) {
          if (typeof p === 'string') {
            item.mediaPaths.push(p as string);
          }
        }
      }
      item.width = typeof o['width'] === 'number' ? o['width'] as number : 0;
      item.height = typeof o['height'] === 'number' ? o['height'] as number : 0;
      return item;
    } catch (e) {
      return null;
    }
  }
}

export function platformName(p: Platform): string {
  switch (p) {
    case Platform.XHS:
      return '小红书';
    case Platform.DOUYIN:
      return '抖音';
    case Platform.INSTAGRAM:
      return 'Instagram';
    case Platform.TIKTOK:
      return 'TikTok';
    case Platform.X:
      return 'X';
    default:
      return '链接';
  }
}
