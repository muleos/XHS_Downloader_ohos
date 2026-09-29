/** Data models ported from core/model/ResolvedNote.kt and data/settings. */
import { JsonNode } from './JsonNode';

/** Port of data/settings/DownloadOptions.kt LivePhotoFormat. */
export enum LivePhotoFormat {
  AUTO = 0,
  STANDARD = 1,
  XIAOMI = 2,
  OPLUS = 3,
  SAMSUNG = 4,
  VIVO = 5,
  VIVO_LEGACY = 6,
  HUAWEI = 7
}

export class MediaCandidate {
  url: string;
  width: number;
  height: number;
  videoBitrate: number;
  size: number;
  codec: string;
  original: boolean;
  watermarked: boolean;

  constructor(url: string, width: number = 0, height: number = 0, videoBitrate: number = 0,
    size: number = 0, codec: string = '', original: boolean = false, watermarked: boolean = false) {
    this.url = url;
    this.width = width;
    this.height = height;
    this.videoBitrate = videoBitrate;
    this.size = size;
    this.codec = codec;
    this.original = original;
    this.watermarked = watermarked;
  }
}

export class ResolvedImage {
  sourceUrl: string;
  originalUrl: string;
  id: string;
  previewUrl: string;
  cover: boolean;
  commentId: string;
  width: number;
  height: number;

  constructor(sourceUrl: string, originalUrl: string = sourceUrl, id: string = sourceUrl,
    previewUrl: string = originalUrl, cover: boolean = false, commentId: string = '',
    width: number = 0, height: number = 0) {
    this.sourceUrl = sourceUrl;
    this.originalUrl = originalUrl;
    this.id = id;
    this.previewUrl = previewUrl;
    this.cover = cover;
    this.commentId = commentId;
    this.width = width;
    this.height = height;
  }
}

export class ResolvedVideo {
  sourceUrl: string;
  originalUrl: string;
  id: string;
  previewUrl: string;
  candidates: MediaCandidate[];

  constructor(sourceUrl: string, originalUrl: string = sourceUrl, id: string = sourceUrl,
    previewUrl: string = '', candidates: MediaCandidate[] = []) {
    this.sourceUrl = sourceUrl;
    this.originalUrl = originalUrl;
    this.id = id;
    this.previewUrl = previewUrl;
    if (candidates.length === 0) {
      this.candidates = [new MediaCandidate(sourceUrl)];
    } else {
      this.candidates = candidates;
    }
  }
}

export class ResolvedLivePhoto {
  image: ResolvedImage;
  video: ResolvedVideo;
  id: string;

  constructor(image: ResolvedImage, video: ResolvedVideo) {
    this.image = image;
    this.video = video;
    this.id = image.id;
  }
}

/** Immutable snapshot of one note. Signed URLs are transport details, never media identities. */
export class ResolvedNote {
  canonicalUrl: string;
  title: string;
  description: string;
  authorName: string;
  authorId: string;
  publishTime: string;
  images: ResolvedImage[];
  videos: ResolvedVideo[];
  livePhotos: ResolvedLivePhoto[];
  noteId: string;
  type: string;
  body: string;
  tags: string[];
  updatedAt: number;
  publishedAt: number;
  interactions: Record<string, string>;
  /** ordered media (images + videos + livePhotos + comment images) */
  items: ResolvedNoteItem[];
  commentsLoaded: boolean;
  commentsHasMore: boolean;

  constructor() {
    this.canonicalUrl = '';
    this.title = '';
    this.description = '';
    this.authorName = '';
    this.authorId = '';
    this.publishTime = '';
    this.images = [];
    this.videos = [];
    this.livePhotos = [];
    this.noteId = '';
    this.type = 'normal';
    this.body = '';
    this.tags = [];
    this.updatedAt = 0;
    this.publishedAt = 0;
    this.interactions = {};
    this.items = [];
    this.commentsLoaded = false;
    this.commentsHasMore = false;
  }

  /** Plain serializable bundle for router params / JSON round-trips. */
  toBundle(): Record<string, Object> {
    return JSON.parse(JSON.stringify({
      'canonicalUrl': this.canonicalUrl,
      'title': this.title,
      'description': this.description,
      'authorName': this.authorName,
      'authorId': this.authorId,
      'publishTime': this.publishTime,
      'images': this.images,
      'videos': this.videos,
      'livePhotos': this.livePhotos,
      'noteId': this.noteId,
      'type': this.type,
      'body': this.body,
      'tags': this.tags,
      'updatedAt': this.updatedAt,
      'publishedAt': this.publishedAt,
      'interactions': this.interactions,
      'items': this.items,
      'commentsLoaded': this.commentsLoaded,
      'commentsHasMore': this.commentsHasMore
    })) as Record<string, Object>;
  }

  static fromBundle(bundle: Record<string, Object>): ResolvedNote {
    const note = new ResolvedNote();
    note.canonicalUrl = String(bundle['canonicalUrl'] ?? '');
    note.title = String(bundle['title'] ?? '');
    note.description = String(bundle['description'] ?? '');
    note.authorName = String(bundle['authorName'] ?? '');
    note.authorId = String(bundle['authorId'] ?? '');
    note.publishTime = String(bundle['publishTime'] ?? '');
    note.images = (bundle['images'] as ResolvedImage[]) ?? [];
    note.videos = (bundle['videos'] as ResolvedVideo[]) ?? [];
    note.livePhotos = (bundle['livePhotos'] as ResolvedLivePhoto[]) ?? [];
    note.noteId = String(bundle['noteId'] ?? '');
    note.type = String(bundle['type'] ?? 'normal');
    note.body = String(bundle['body'] ?? '');
    note.tags = (bundle['tags'] as string[]) ?? [];
    note.updatedAt = Number(bundle['updatedAt'] ?? 0);
    note.publishedAt = Number(bundle['publishedAt'] ?? 0);
    note.interactions = (bundle['interactions'] as Record<string, string>) ?? {};
    note.items = (bundle['items'] as ResolvedNoteItem[]) ?? [];
    note.commentsLoaded = Boolean(bundle['commentsLoaded'] ?? false);
    note.commentsHasMore = Boolean(bundle['commentsHasMore'] ?? false);
    return note;
  }
}

/** Tagged union of media items in display order. */
export class ResolvedNoteItem {
  kind: 'image' | 'video' | 'live';
  image: ResolvedImage | null;
  video: ResolvedVideo | null;
  live: ResolvedLivePhoto | null;

  private constructor(kind: 'image' | 'video' | 'live') {
    this.kind = kind;
    this.image = null;
    this.video = null;
    this.live = null;
  }

  static ofImage(image: ResolvedImage): ResolvedNoteItem {
    const item = new ResolvedNoteItem('image');
    item.image = image;
    return item;
  }

  static ofVideo(video: ResolvedVideo): ResolvedNoteItem {
    const item = new ResolvedNoteItem('video');
    item.video = video;
    return item;
  }

  static ofLive(live: ResolvedLivePhoto): ResolvedNoteItem {
    const item = new ResolvedNoteItem('live');
    item.live = live;
    return item;
  }
}

// ---------------------------------------------------------------------------
// Settings (ported from data/settings)

export enum ImageFormat {
  AUTO = 0,
  JPEG = 1,
  PNG = 2,
  WEBP = 3
}

export enum VideoPreference {
  RESOLUTION = 0,
  BITRATE = 1,
  SIZE = 2,
  COMPATIBILITY = 3
}

export enum LivePhotoMode {
  MERGED = 0,
  SEPARATE = 1,
  STILL = 2
}

export class DownloadOptions {
  imageFormat: ImageFormat = ImageFormat.AUTO;
  videoPreference: VideoPreference = VideoPreference.RESOLUTION;
  imageDownload: boolean = true;
  videoDownload: boolean = true;
  videoCoverDownload: boolean = false;
  commentImageDownload: boolean = false;
  livePhotoMode: LivePhotoMode = LivePhotoMode.MERGED;
  livePhotoFormat: LivePhotoFormat = LivePhotoFormat.AUTO;
  skipExisting: boolean = false;
  authorArchive: boolean = false;
  noteArchive: boolean = false;
  noteFormatNone: boolean = true; // v1: TXT/MD saved on demand from detail page
  writePublishTime: boolean = false;
  timeoutSeconds: number = 45;
  maxRetries: number = 3;
  proxy: string = '';
  proxyDownload: boolean = false;
  useWebSession: boolean = true;

  static fromJson(node: JsonNode | null): DownloadOptions {
    const o = new DownloadOptions();
    if (node === null || !node.isObject()) {
      return o;
    }
    o.imageFormat = node.optNumber('imageFormat', ImageFormat.AUTO) as ImageFormat;
    o.videoPreference = node.optNumber('videoPreference', VideoPreference.RESOLUTION) as VideoPreference;
    o.imageDownload = node.optBool('imageDownload', true);
    o.videoDownload = node.optBool('videoDownload', true);
    o.videoCoverDownload = node.optBool('videoCoverDownload', false);
    o.commentImageDownload = node.optBool('commentImageDownload', false);
    o.livePhotoMode = node.optNumber('livePhotoMode', LivePhotoMode.MERGED) as LivePhotoMode;
    o.skipExisting = node.optBool('skipExisting', false);
    o.authorArchive = node.optBool('authorArchive', false);
    o.noteArchive = node.optBool('noteArchive', false);
    o.writePublishTime = node.optBool('writePublishTime', false);
    o.timeoutSeconds = node.optNumber('timeoutSeconds', 45);
    o.maxRetries = node.optNumber('maxRetries', 3);
    o.proxy = node.optString('proxy', '');
    o.proxyDownload = node.optBool('proxyDownload', false);
    o.useWebSession = node.optBool('useWebSession', true);
    return o;
  }

  toJson(): Record<string, Object> {
    return {
      'imageFormat': this.imageFormat,
      'videoPreference': this.videoPreference,
      'imageDownload': this.imageDownload,
      'videoDownload': this.videoDownload,
      'videoCoverDownload': this.videoCoverDownload,
      'commentImageDownload': this.commentImageDownload,
      'livePhotoMode': this.livePhotoMode,
      'skipExisting': this.skipExisting,
      'authorArchive': this.authorArchive,
      'noteArchive': this.noteArchive,
      'writePublishTime': this.writePublishTime,
      'timeoutSeconds': this.timeoutSeconds,
      'maxRetries': this.maxRetries,
      'proxy': this.proxy,
      'proxyDownload': this.proxyDownload,
      'useWebSession': this.useWebSession
    } as Record<string, Object>;
  }
}

export class AppSettings {
  downloadOptions: DownloadOptions = new DownloadOptions();
  createLivePhotos: boolean = true;
  useCustomNamingFormat: boolean = false;
  customNamingTemplate: string = NamingFormatDefaults.DEFAULT_TEMPLATE;
  showMediaResolution: boolean = false;
  keepScreenOn: boolean = false;
  showClipboardBubble: boolean = true;
  autoReadClipboard: boolean = false;
  manualInputLinks: boolean = false;
  customStorageUri: string = '';
  customStorageDisplayName: string = '';
  checkExistingFilesBeforeSave: boolean = true;

  static fromJson(node: JsonNode | null): AppSettings {
    const s = new AppSettings();
    if (node === null || !node.isObject()) {
      return s;
    }
    s.downloadOptions = DownloadOptions.fromJson(node.optObject('downloadOptions'));
    s.createLivePhotos = node.optBool('createLivePhotos', true);
    s.useCustomNamingFormat = node.optBool('useCustomNamingFormat', false);
    s.customNamingTemplate = node.optString('customNamingTemplate', NamingFormatDefaults.DEFAULT_TEMPLATE);
    s.showMediaResolution = node.optBool('showMediaResolution', false);
    s.keepScreenOn = node.optBool('keepScreenOn', false);
    s.showClipboardBubble = node.optBool('showClipboardBubble', true);
    s.autoReadClipboard = node.optBool('autoReadClipboard', false);
    s.manualInputLinks = node.optBool('manualInputLinks', false);
    s.customStorageUri = node.optString('customStorageUri', '');
    s.customStorageDisplayName = node.optString('customStorageDisplayName', '');
    s.checkExistingFilesBeforeSave = node.optBool('checkExistingFilesBeforeSave', true);
    return s;
  }

  toJson(): Record<string, Object> {
    return {
      'downloadOptions': this.downloadOptions.toJson(),
      'createLivePhotos': this.createLivePhotos,
      'useCustomNamingFormat': this.useCustomNamingFormat,
      'customNamingTemplate': this.customNamingTemplate,
      'showMediaResolution': this.showMediaResolution,
      'keepScreenOn': this.keepScreenOn,
      'showClipboardBubble': this.showClipboardBubble,
      'autoReadClipboard': this.autoReadClipboard,
      'manualInputLinks': this.manualInputLinks,
      'customStorageUri': this.customStorageUri,
      'customStorageDisplayName': this.customStorageDisplayName,
      'checkExistingFilesBeforeSave': this.checkExistingFilesBeforeSave
    } as Record<string, Object>;
  }
}

export class NamingFormatDefaults {
  static readonly TOKEN_USERNAME: string = 'username';
  static readonly TOKEN_USER_ID: string = 'userId';
  static readonly TOKEN_TITLE: string = 'title';
  static readonly TOKEN_POST_ID: string = 'postId';
  static readonly TOKEN_PUBLISH_TIME: string = 'publishTime';
  static readonly TOKEN_INDEX: string = 'index';
  static readonly TOKEN_INDEX_PADDED: string = 'index_padded';
  static readonly TOKEN_DOWNLOAD_TIMESTAMP: string = 'downloadTimestamp';
  static readonly DEFAULT_TEMPLATE: string =
    NamingFormatDefaults.placeholder(NamingFormatDefaults.TOKEN_TITLE) + '(' +
    NamingFormatDefaults.placeholder(NamingFormatDefaults.TOKEN_USERNAME) + ')_' +
    NamingFormatDefaults.placeholder(NamingFormatDefaults.TOKEN_PUBLISH_TIME);

  static placeholder(key: string): string {
    return '{' + key + '}';
  }
}

// ---------------------------------------------------------------------------
// Download records (ported from data/tasks/RecordExport.kt)

export class DownloadRecord {
  taskId: number;
  noteId: string;
  author: string;
  title: string;
  mediaId: string;
  state: string;
  createdAt: number;

  constructor(taskId: number, noteId: string, author: string, title: string, mediaId: string,
    state: string, createdAt: number) {
    this.taskId = taskId;
    this.noteId = noteId;
    this.author = author;
    this.title = title;
    this.mediaId = mediaId;
    this.state = state;
    this.createdAt = createdAt;
  }

  toCsvRow(): string {
    const cells: string[] = [
      String(this.taskId), this.noteId, this.author, this.title, this.mediaId, this.state, String(this.createdAt)
    ];
    const escaped: string[] = [];
    for (const cell of cells) {
      escaped.push(csvCell(cell));
    }
    return escaped.join(',') + '\r\n';
  }

  toJsonText(): string {
    return JSON.stringify({
      'taskId': this.taskId,
      'noteId': this.noteId,
      'author': this.author,
      'title': this.title,
      'mediaId': this.mediaId,
      'state': this.state,
      'createdAt': this.createdAt
    });
  }
}

export function csvCell(value: string): string {
  const first = value.length > 0 ? value[0] : '';
  let safe = value;
  if (first === '=' || first === '+' || first === '-' || first === '@') {
    safe = "'" + value;
  }
  return '"' + safe.replace(/"/g, '""') + '"';
}
