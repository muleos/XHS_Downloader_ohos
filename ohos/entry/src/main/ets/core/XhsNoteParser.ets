/**
 * Ported from data/xhs/XhsNoteParser.kt — 1:1 logic.
 * Parses window.__INITIAL_STATE__ out of note pages, normalizes the JS
 * object literal, deep-finds note objects and resolves media with
 * live-photo stream detection (streamType 259/309 = watermarked) and
 * comment-image BFS.
 */
import { JsonNode } from './JsonNode';
import { MediaCandidate, ResolvedImage, ResolvedLivePhoto, ResolvedNote, ResolvedNoteItem, ResolvedVideo } from './models';

interface CommentImagesResult {
  images: ResolvedImage[];
  hasMore: boolean;
}

export class XhsLivePhotoPair {
  imageUrl: string;
  videoUrl: string;

  constructor(imageUrl: string, videoUrl: string) {
    this.imageUrl = imageUrl;
    this.videoUrl = videoUrl;
  }
}

export class ParsedXhsNote {
  mediaUrls: string[];
  livePhotos: XhsLivePhotoPair[];
  description: string;
  userName: string;
  userId: string;
  title: string;
  publishTime: string;
  containsVideo: boolean;
  originalUrlByTransformed: Map<string, string>;
  resolved: ResolvedNote | null;

  constructor() {
    this.mediaUrls = [];
    this.livePhotos = [];
    this.description = '';
    this.userName = '';
    this.userId = '';
    this.title = '';
    this.publishTime = '';
    this.containsVideo = false;
    this.originalUrlByTransformed = new Map<string, string>();
    this.resolved = null;
  }

  hasRequiredFields(): boolean {
    return this.userName.length > 0 && this.userId.length > 0;
  }
}

export class XhsNoteParser {
  private urlTransformer: (url: string) => string;
  private logError: (message: string) => void;

  constructor(urlTransformer: (url: string) => string = (u: string): string => u,
    logError: (message: string) => void = (m: string): void => {}) {
    this.urlTransformer = urlTransformer;
    this.logError = logError;
  }

  parse(html: string, expectedNoteId: string = '', canonicalUrl: string = ''): ParsedXhsNote {
    if (html === null || html.trim().length === 0) {
      return this.empty();
    }
    const root = this.parseInitialStateRootFromHtml(html);
    let notes: JsonNode[] = [];
    if (root !== null) {
      notes = this.findNoteObjects(root).filter((n: JsonNode): boolean => this.isLikelyNoteObject(n));
    }
    let selected: JsonNode | null = null;
    if (expectedNoteId.length > 0) {
      for (const note of notes) {
        if (note.optString('noteId') === expectedNoteId) {
          selected = note;
          break;
        }
      }
      if (selected === null && notes.length === 1 && notes[0].optString('noteId').length === 0) {
        selected = notes[0];
      }
    } else if (notes.length === 1) {
      selected = notes[0];
    }
    if (selected === null) {
      if (notes.length > 0) {
        return this.empty();
      }
      const regex = /https?:\/\/[^\s"<>]+?\.(?:jpg|jpeg|png|gif|webp|mp4|mov)(?:\?[^\s"<>]*)?/gi;
      const urls: string[] = [];
      let m: RegExpExecArray | null = regex.exec(html);
      while (m !== null) {
        if (urls.indexOf(m[0]) < 0) {
          urls.push(m[0]);
        }
        m = regex.exec(html);
      }
      const legacy = this.empty();
      legacy.mediaUrls = urls;
      for (const u of urls) {
        const lower = u.toLowerCase();
        if (lower.includes('.mp4') || lower.includes('.mov')) {
          legacy.containsVideo = true;
          break;
        }
      }
      return legacy;
    }
    let detail: JsonNode | null = null;
    if (root !== null) {
      const noteId = selected.optString('noteId');
      const mobile = root.optObject('noteData') !== null ?
        root.optObject('noteData')!.optObject('data') : null;
      const mobileNote = mobile !== null ? mobile.optObject('noteData') : null;
      const mobileMatches = mobileNote !== null && noteId.length > 0 && mobileNote.optString('noteId') === noteId;
      const noteRoot = root.optObject('note');
      const detailMap = noteRoot !== null ? noteRoot.optObject('noteDetailMap') : null;
      const fromMap = detailMap !== null && noteId.length > 0 ? detailMap.optObject(noteId) : null;
      detail = fromMap !== null ? fromMap : (mobileMatches ? mobile : null);
    }
    const note = this.parseDetail(detail !== null ? detail : selected, canonicalUrl, expectedNoteId);
    const urls: string[] = [];
    const originals = new Map<string, string>();
    for (const item of note.items) {
      if (item.kind === 'live' && item.live !== null) {
        urls.push(item.live.image.sourceUrl);
        urls.push(item.live.video.sourceUrl);
        originals.set(item.live.image.sourceUrl, item.live.image.originalUrl);
        originals.set(item.live.video.sourceUrl, item.live.video.originalUrl);
      } else if (item.kind === 'video' && item.video !== null) {
        urls.push(item.video.sourceUrl);
        originals.set(item.video.sourceUrl, item.video.originalUrl);
      } else if (item.kind === 'image' && item.image !== null) {
        urls.push(item.image.sourceUrl);
        originals.set(item.image.sourceUrl, item.image.originalUrl);
      }
    }
    const result = new ParsedXhsNote();
    result.mediaUrls = urls;
    result.livePhotos = note.livePhotos.map((lp: ResolvedLivePhoto): XhsLivePhotoPair =>
      new XhsLivePhotoPair(lp.image.sourceUrl, lp.video.sourceUrl));
    result.description = note.description;
    result.userName = note.authorName;
    result.userId = note.authorId;
    result.title = note.title;
    result.publishTime = note.publishTime;
    result.containsVideo = note.videos.length > 0 || note.livePhotos.length > 0;
    result.originalUrlByTransformed = originals;
    result.resolved = note;
    return result;
  }

  /** Preserve sibling comments when decoding a noteDetailMap entry or WebView result. */
  parseDetail(detail: JsonNode, canonicalUrl: string, expectedNoteId: string = ''): ResolvedNote {
    const note = detail.optObject('note') !== null ? detail.optObject('note')! :
      (detail.optObject('noteData') !== null ? detail.optObject('noteData')! : detail);
    const comments = detail.optObject('comments') !== null ? detail.optObject('comments')! :
      (detail.optObject('commentData') !== null ? detail.optObject('commentData')! : note.optObject('comments'));
    return this.parseNote(note, canonicalUrl, expectedNoteId, comments);
  }

  parseNote(note: JsonNode, canonicalUrl: string, expectedNoteId: string = '',
    comments: JsonNode | null = note.optObject('comments')): ResolvedNote {
    let noteId = note.optString('noteId');
    if (noteId.length === 0 && expectedNoteId.length > 0) {
      noteId = expectedNoteId;
    }
    const imageListNode = note.opt('imageList') !== null ? note.opt('imageList')! : note.opt('images');
    let imageList: JsonNode[] = [];
    if (imageListNode !== null) {
      imageList = imageListNode.optArray('__self');
      if (imageList.length === 0) {
        imageList = this.selfArray(imageListNode);
      }
    }
    const mainVideo = note.optObject('video');
    let type = note.optString('type');
    if (type.length === 0) {
      const firstImage = imageList.length > 0 ? imageList[0].optObject('stream') : null;
      type = mainVideo !== null && imageList.length <= 1 && firstImage === null ? 'video' : 'normal';
    }
    const isVideoNote = type === 'video';
    const items: ResolvedNoteItem[] = [];
    for (let index = 0; index < imageList.length; index++) {
      const item = imageList[index];
      if (!item.isObject()) {
        continue;
      }
      let original = item.optString('urlDefault');
      if (original.length === 0) {
        original = item.optString('url');
      }
      if (original.length === 0) {
        const info = item.optArray('infoList');
        for (const infoItem of info) {
          const url = infoItem.optString('url');
          if (url.length > 0) {
            original = url;
            break;
          }
        }
      }
      if (original.length === 0) {
        const traceId = item.optString('traceId');
        if (traceId.length > 0) {
          original = 'https://sns-img-qc.xhscdn.com/' + traceId;
        }
      }
      if (!this.isHttp(original)) {
        continue;
      }
      const streams = this.distinctByUrl(
        this.videoCandidates(item.optObject('livePhoto')).concat(this.videoCandidates(item)));
      streams.sort((a: MediaCandidate, b: MediaCandidate): number => {
        if (a.original !== b.original) {
          return a.original ? 1 : -1; // original first (compareByDescending)
        }
        return (a.watermarked ? 1 : 0) - (b.watermarked ? 1 : 0);
      });
      const isCover = isVideoNote && streams.length === 0;
      const image = new ResolvedImage(this.urlTransformer(original), original,
        noteId + ':' + (isCover ? 'cover' : 'image') + ':' + (index + 1), original, isCover,
        '', item.optNumber('width'), item.optNumber('height'));
      if (streams.length > 0) {
        items.push(ResolvedNoteItem.ofLive(new ResolvedLivePhoto(image,
          new ResolvedVideo(streams[0].url, streams[0].url, noteId + ':live:' + (index + 1), original, streams))));
      } else {
        items.push(ResolvedNoteItem.ofImage(image));
      }
    }
    if (mainVideo !== null && (isVideoNote || !note.has('type'))) {
      const distinct = this.videoCandidates(mainVideo);
      if (distinct.length > 0) {
        const preview = items.length > 0 ? this.previewOf(items[0]) : '';
        items.push(ResolvedNoteItem.ofVideo(new ResolvedVideo(distinct[0].url, distinct[0].url,
          noteId + ':video', preview, distinct)));
      }
    }
    const commentMedia = this.parseCommentImages(comments, noteId);
    for (const image of commentMedia.images) {
      items.push(ResolvedNoteItem.ofImage(image));
    }
    const user = note.optObject('user') !== null ? note.optObject('user')! : note.optObject('user_info');
    const emptyUser = JsonNode.parse('{}')!;
    const userNode = user !== null ? user : emptyUser;
    const title = note.optString('title');
    let body = note.optString('desc');
    if (body.length === 0) {
      body = note.optString('description');
    }
    const tagsNode = note.opt('tagList');
    const tags: string[] = [];
    if (tagsNode !== null) {
      for (const tag of tagsNode.optArray('__self')) {
        const name = tag.optString('name');
        if (name.length > 0) {
          tags.push(name);
        }
      }
    }
    const published = note.optNumber('time');
    const interact = note.optObject('interactInfo');
    const resolved = new ResolvedNote();
    resolved.canonicalUrl = canonicalUrl;
    resolved.noteId = noteId;
    resolved.type = type;
    resolved.title = title;
    resolved.body = body;
    const descParts: string[] = [];
    if (title.length > 0) {
      descParts.push(title);
    }
    if (body.length > 0) {
      descParts.push(body);
    }
    resolved.description = descParts.length > 0 ? descParts.join('\n') : '';
    resolved.authorName = this.firstNonBlank(userNode, ['nickname', 'nickName', 'name', 'userName']);
    resolved.authorId = this.firstNonBlank(userNode, ['userId', 'user_id', 'id', 'redId']);
    resolved.publishTime = published > 0 ? String(published) :
      (note.optString('timeText').length > 0 ? note.optString('timeText') : '');
    resolved.publishedAt = published > 0 ? published : 0;
    resolved.updatedAt = note.optNumber('lastUpdateTime') > 0 ? note.optNumber('lastUpdateTime') : 0;
    resolved.tags = tags;
    const interactions: Record<string, string> = {};
    const keys = ['likedCount', 'collectedCount', 'commentCount', 'shareCount'];
    for (const k of keys) {
      interactions[k] = interact !== null ? interact.optString(k, '') : '';
    }
    resolved.interactions = interactions;
    for (const item of items) {
      if (item.kind === 'image' && item.image !== null) {
        resolved.images.push(item.image);
      } else if (item.kind === 'video' && item.video !== null) {
        resolved.videos.push(item.video);
      } else if (item.kind === 'live' && item.live !== null) {
        resolved.livePhotos.push(item.live);
      }
    }
    resolved.items = items;
    const list = comments !== null ?
      (comments.opt('list') !== null ? comments.opt('list')! : comments.opt('comments')) : null;
    const firstRequestFinish = comments !== null ? comments.optBool('firstRequestFinish', true) : true;
    resolved.commentsLoaded = list !== null && firstRequestFinish;
    resolved.commentsHasMore = commentMedia.hasMore;
    return resolved;
  }

  private selfArray(node: JsonNode): JsonNode[] {
    // A JsonNode that already wraps an array exposes elements via at(i)/length().
    const out: JsonNode[] = [];
    for (let i = 0; i < node.length(); i++) {
      const element = node.at(i);
      if (element !== null) {
        out.push(element);
      }
    }
    return out;
  }

  private previewOf(item: ResolvedNoteItem): string {
    if (item.kind === 'image' && item.image !== null) {
      return item.image.previewUrl;
    }
    if (item.kind === 'live' && item.live !== null) {
      return item.live.image.previewUrl;
    }
    return '';
  }

  private firstNonBlank(node: JsonNode, keys: string[]): string {
    for (const key of keys) {
      const value = node.optString(key);
      if (value.length > 0) {
        return value;
      }
    }
    return '';
  }

  private parseCommentImages(comments: JsonNode | null, noteId: string): CommentImagesResult {
    const images: ResolvedImage[] = [];
    const queue: JsonNode[] = [];
    const seen: string[] = [];
    let hasMore = comments !== null && comments.optBool('hasMore', false);
    const enqueue = (list: JsonNode[] | null): void => {
      if (list !== null) {
        for (const item of list) {
          if (item.isObject()) {
            queue.push(item);
          }
        }
      }
    };
    if (comments !== null) {
      const list = comments.opt('list') !== null ? comments.opt('list')! : comments.opt('comments');
      if (list !== null) {
        enqueue(this.selfArray(list));
      }
    }
    let head = 0;
    while (head < queue.length) {
      const comment = queue[head++];
      const commentNoteId = comment.optString('noteId');
      if (commentNoteId.length > 0 && commentNoteId !== noteId) {
        continue;
      }
      if (comment.optBool('invalid')) {
        continue;
      }
      const commentId = comment.optString('id');
      if (commentId.length === 0 || seen.indexOf(commentId) >= 0) {
        continue;
      }
      seen.push(commentId);
      if (comment.optBool('subCommentHasMore') || comment.optBool('hasMore')) {
        hasMore = true;
      }
      const subComments = comment.opt('subComments');
      if (subComments !== null) {
        enqueue(this.selfArray(subComments));
      }
      const pictures = comment.opt('pictures');
      if (pictures === null) {
        continue;
      }
      const pictureList = this.selfArray(pictures);
      for (let index = 0; index < pictureList.length; index++) {
        const picture = pictureList[index];
        if (!picture.isObject()) {
          continue;
        }
        const infoList = picture.optArray('infoList');
        let original = '';
        const urlDefault = picture.optString('urlDefault');
        if (this.isHttp(urlDefault)) {
          original = urlDefault;
        } else {
          for (const variant of infoList) {
            if (variant.optString('imageScene') === 'WB_DFT') {
              const url = variant.optString('url');
              if (this.isHttp(url)) {
                original = url;
                break;
              }
            }
          }
        }
        if (original.length === 0) {
          const url = picture.optString('url');
          if (this.isHttp(url)) {
            original = url;
          }
        }
        if (original.length === 0) {
          for (const variant of infoList) {
            const url = variant.optString('url');
            if (this.isHttp(url)) {
              original = url;
              break;
            }
          }
        }
        if (original.length === 0) {
          const urlPre = picture.optString('urlPre');
          if (this.isHttp(urlPre)) {
            original = urlPre;
          }
        }
        if (original.length === 0) {
          continue;
        }
        const previewCandidate = picture.optString('urlPre');
        const preview = this.isHttp(previewCandidate) ? previewCandidate : original;
        images.push(new ResolvedImage(this.urlTransformer(original), original,
          noteId + ':comment:' + commentId + ':' + (index + 1), preview, false, commentId,
          picture.optNumber('width'), picture.optNumber('height')));
      }
    }
    return { images: images, hasMore: hasMore } as CommentImagesResult;
  }

  private videoCandidates(video: JsonNode | null): MediaCandidate[] {
    if (video === null || !video.isObject()) {
      return [];
    }
    let key = '';
    const consumer = video.optObject('consumer');
    if (consumer !== null) {
      const originKey = consumer.opt('originVideoKey');
      if (originKey !== null && originKey.isString() && originKey.asString().length > 0) {
        key = originKey.asString();
      }
    }
    if (key.length === 0) {
      const directKey = video.opt('originVideoKey');
      if (directKey !== null && directKey.isString() && directKey.asString().length > 0) {
        key = directKey.asString();
      }
    }
    const out: MediaCandidate[] = [];
    if (key.length > 0) {
      const url = this.isHttp(key) ? key : 'https://sns-video-bd.xhscdn.com/' + this.trimSlashes(key);
      out.push(new MediaCandidate(url, 0, 0, 0, 0, '', true, false));
    }
    const media = video.optObject('media');
    const mediaStream = media !== null ? media.optObject('stream') : null;
    out.push(...this.candidates(mediaStream));
    out.push(...this.candidates(video.optObject('stream')));
    return this.distinctByUrl(out).sort((a: MediaCandidate, b: MediaCandidate): number =>
      (a.watermarked ? 1 : 0) - (b.watermarked ? 1 : 0));
  }

  private candidates(stream: JsonNode | null): MediaCandidate[] {
    const out: MediaCandidate[] = [];
    if (stream === null || !stream.isObject()) {
      return out;
    }
    stream.forEachEntry((codec: string, arrayNode: JsonNode): void => {
      if (arrayNode.length() === 0 && !arrayNode.isObject()) {
        return;
      }
      for (let index = 0; index < arrayNode.length(); index++) {
        const item = arrayNode.at(index);
        if (item === null) {
          continue;
        }
        if (!item.isObject()) {
          const raw = item.asString();
          if (this.isHttp(raw)) {
            out.push(new MediaCandidate(raw, 0, 0, 0, 0, codec, false, false));
          }
          continue;
        }
        const urls: string[] = [];
        const backups = item.optArray('backupUrls');
        for (const backup of backups) {
          urls.push(backup.asString());
        }
        urls.push(item.optString('masterUrl'));
        urls.push(item.optString('url'));
        const seenUrl: string[] = [];
        for (const url of urls) {
          if (this.isHttp(url) && seenUrl.indexOf(url) < 0) {
            seenUrl.push(url);
            const streamType = item.optNumber('streamType');
            const streamDesc = item.optString('streamDesc');
            const watermarked = streamType === 259 || streamType === 309 ||
              streamDesc.toLowerCase() === 'web_livephoto_19';
            out.push(new MediaCandidate(url, item.optNumber('width'), item.optNumber('height'),
              item.optNumber('videoBitrate'), item.optNumber('size'), codec, false, watermarked));
          }
        }
      }
    });
    return out;
  }

  private distinctByUrl(list: MediaCandidate[]): MediaCandidate[] {
    const out: MediaCandidate[] = [];
    for (const candidate of list) {
      if (out.findIndex((c: MediaCandidate): boolean => c.url === candidate.url) < 0) {
        out.push(candidate);
      }
    }
    return out;
  }

  private isHttp(value: string): boolean {
    return value.startsWith('https://') || value.startsWith('http://');
  }

  private trimSlashes(value: string): string {
    let s = value;
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    return s;
  }

  private empty(): ParsedXhsNote {
    return new ParsedXhsNote();
  }

  // -------------------------------------------------------------------------

  private parseInitialStateRootFromHtml(html: string): JsonNode | null {
    const start = html.indexOf('window.__INITIAL_STATE__');
    if (start < 0) {
      return null;
    }
    const end = html.indexOf('</script>', start);
    if (end < 0) {
      return null;
    }
    const script = html.substring(start, end);
    const equals = script.indexOf('=');
    if (equals < 0) {
      return null;
    }
    let objectLiteral = this.extractFirstJsObjectLiteral(script.substring(equals + 1).trim());
    if (objectLiteral === null) {
      objectLiteral = script.substring(equals + 1).trim();
    }
    objectLiteral = objectLiteral.trim();
    if (objectLiteral.endsWith(';')) {
      objectLiteral = objectLiteral.substring(0, objectLiteral.length - 1).trim();
    }
    objectLiteral = this.normalizeStateLiteral(objectLiteral);
    const root = JsonNode.parse(objectLiteral);
    if (root === null) {
      this.logError('Unable to parse __INITIAL_STATE__');
      return null;
    }
    return root;
  }

  private extractFirstJsObjectLiteral(snippet: string): string | null {
    let inString = false;
    let quote = '';
    let escaped = false;
    let depth = 0;
    let start = -1;
    for (let index = 0; index < snippet.length; index++) {
      const ch = snippet[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === quote) {
          inString = false;
        }
        continue;
      }
      if (ch === '\'' || ch === '"') {
        inString = true;
        quote = ch;
        continue;
      }
      if (ch === '{') {
        if (depth === 0) {
          start = index;
        }
        depth++;
      } else if (ch === '}') {
        if (depth > 0) {
          depth--;
          if (depth === 0 && start >= 0) {
            return snippet.substring(start, index + 1);
          }
        }
      }
    }
    return null;
  }

  private normalizeStateLiteral(input: string): string {
    let out = '';
    let quote = '';
    let escaped = false;
    let index = 0;
    while (index < input.length) {
      const ch = input[index];
      if (quote.length > 0) {
        if (ch.charCodeAt(0) < 32) {
          out += '\\u' + ch.charCodeAt(0).toString(16).padStart(4, '0');
        } else {
          out += ch;
        }
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === quote) {
          quote = '';
        }
        index++;
        continue;
      }
      if (ch === '"' || ch === '\'') {
        quote = ch;
      }
      const prevChar = index > 0 ? input[index - 1] : '';
      const nextChar = index + 9 < input.length ? input[index + 9] : '';
      if (input.startsWith('undefined', index) && !this.isJsIdentifierChar(prevChar) &&
        !this.isJsIdentifierChar(nextChar)) {
        out += 'null';
        index += 9;
        continue;
      }
      if (input.startsWith('new Map([])', index)) {
        out += '[]';
        index += 11;
        continue;
      }
      const code = ch.charCodeAt(0);
      if (code >= 32 || ch === '\n' || ch === '\r' || ch === '\t') {
        out += ch;
      }
      index++;
    }
    return out;
  }

  private isJsIdentifierChar(ch: string): boolean {
    if (ch === null || ch.length === 0) {
      return false;
    }
    if (/[A-Za-z0-9_$]/.test(ch)) {
      return true;
    }
    return ch.charCodeAt(0) > 127;
  }

  private isLikelyNoteObject(obj: JsonNode): boolean {
    try {
      if (obj.has('noteId') && (obj.has('title') || obj.has('desc'))) {
        return true;
      }
      const imageArray = obj.opt('imageList') !== null ? obj.opt('imageList')! : obj.opt('images');
      if (imageArray === null) {
        const video = obj.optObject('video');
        return video !== null && (video.has('consumer') || video.has('media'));
      }
      const image = imageArray.at(0);
      if (image === null) {
        const video = obj.optObject('video');
        return video !== null && (video.has('consumer') || video.has('media'));
      }
      return image.has('urlDefault') || image.has('url') || image.has('traceId') || image.has('infoList');
    } catch (e) {
      return false;
    }
  }

  private findNoteObjects(root: JsonNode): JsonNode[] {
    const notes: JsonNode[] = [];
    const seenIds: string[] = [];

    const addCandidate = (note: JsonNode | null): void => {
      if (note === null || !note.isObject()) {
        return;
      }
      if (note.keys().length === 0) {
        return;
      }
      const id = note.optString('noteId');
      if (id.length > 0) {
        if (seenIds.indexOf(id) >= 0) {
          return;
        }
        seenIds.push(id);
      }
      notes.push(note);
    };

    try {
      const noteRoot = root.optObject('note');
      if (noteRoot !== null) {
        const detailMap = noteRoot.optObject('noteDetailMap');
        if (detailMap !== null) {
          detailMap.forEachEntry((key: string, value: JsonNode): void => {
            const entryNote = value.optObject('note');
            if (entryNote !== null) {
              addCandidate(entryNote);
            }
          });
        } else {
          const nested = noteRoot.optObject('note');
          const feedItems = noteRoot.optObject('feed') !== null ?
            noteRoot.optObject('feed')!.opt('items') : null;
          if (nested !== null) {
            addCandidate(nested);
          } else if (feedItems !== null) {
            for (let index = 0; index < feedItems.length(); index++) {
              const item = feedItems.at(index);
              if (item !== null && item.isObject()) {
                addCandidate(item);
              }
            }
          } else {
            addCandidate(noteRoot);
          }
        }
      }
      const feed = root.optObject('feed');
      const feedItems = feed !== null ? feed.opt('items') : null;
      if (feedItems !== null) {
        for (let index = 0; index < feedItems.length(); index++) {
          const item = feedItems.at(index);
          if (item !== null && item.isObject()) {
            addCandidate(item);
          }
        }
      }
      const noteData = root.optObject('noteData');
      const data = noteData !== null ? noteData.optObject('data') : null;
      if (data !== null) {
        const candidate = data.optObject('noteData') !== null ? data.optObject('noteData')! : data.optObject('note');
        addCandidate(candidate);
      }

      let hasLikely = false;
      for (const note of notes) {
        if (this.isLikelyNoteObject(note)) {
          hasLikely = true;
          break;
        }
      }
      if (notes.length === 0 || !hasLikely) {
        // Deep find: BFS over the whole tree.
        const stack: JsonNode[] = [root];
        let visited = 0;
        let head = 0;
        while (head < stack.length && visited < 50000 && notes.length < 50) {
          const current = stack[head++];
          visited++;
          const nestedNote = current.optObject('note');
          if (nestedNote !== null) {
            stack.push(nestedNote);
          }
          if (this.isLikelyNoteObject(current)) {
            addCandidate(current);
          }
          for (const key of current.keys()) {
            const value = current.opt(key);
            if (value !== null && (value.isObject() || value.length() > 0)) {
              stack.push(value);
            }
          }
        }
      }
    } catch (e) {
      this.logError('Unable to find note objects');
    }
    return notes;
  }
}
