/**
 * Ported from domain/download/NoteOutput.kt — shared naming and candidate policy.
 * Image "format" conversion is CDN URL rewriting (sns-img-bd / ci.xiaohongshu.com
 * imageView2), not local transcoding — identical to Android.
 */
import { ImageFormat, VideoPreference, AppSettings, ResolvedImage, ResolvedNote, ResolvedVideo,
  LivePhotoMode, DownloadOptions } from './models';
import { Sha256 } from './Sha256';

export class NoteOutput {
  /** Ordered media filter policy (same rules as eligible()). */
  static isEligibleItem(note: ResolvedNote, itemIndex: number, options: DownloadOptions, forSelection: boolean): boolean {
    const items = note.items;
    if (itemIndex < 0 || itemIndex >= items.length) {
      return false;
    }
    const item = items[itemIndex];
    if (item.kind === 'image' && item.image !== null) {
      if (item.image.commentId.length > 0) {
        return options.commentImageDownload;
      }
      if (item.image.cover) {
        return forSelection || options.videoCoverDownload;
      }
      return options.imageDownload;
    }
    if (item.kind === 'video') {
      return options.videoDownload;
    }
    // live
    return options.imageDownload || (options.videoDownload && options.livePhotoMode !== LivePhotoMode.STILL);
  }

  /** CDN URL rewrite for images. AUTO = original quality; else imageView2 format. */
  static imageUrls(image: ResolvedImage, format: ImageFormat): string[] {
    const raw = image.originalUrl;
    const m = raw.match(/^https?:\/\/([^/?#]+)(\/[^#?]*)?/i);
    let preferred = '';
    if (m !== null) {
      const host = (m[1] === undefined ? '' : m[1]).toLowerCase();
      const path = (m[2] === undefined ? '' : m[2]).replace(/^\/+/, '');
      const parts = path.length > 0 ? path.split('/') : [];
      let segs = parts;
      if (parts.length > 2 && /^[a-fA-F0-9]{32}$/.test(parts[1])) {
        segs = parts.slice(2);
      }
      let joined = segs.join('/');
      const bang = joined.indexOf('!');
      if (bang >= 0) {
        joined = joined.substring(0, bang);
      }
      const knownCdn = host.endsWith('.xhscdn.com') || host.endsWith('.xiaohongshu.com');
      if (knownCdn && joined.length > 0) {
        if (format === ImageFormat.AUTO) {
          preferred = 'https://sns-img-bd.xhscdn.com/' + joined;
        } else {
          const fmt = format === ImageFormat.JPEG ? 'jpeg' : (format === ImageFormat.PNG ? 'png' : 'webp');
          preferred = 'https://ci.xiaohongshu.com/' + joined + '?imageView2/format/' + fmt;
        }
      }
    }
    const out: string[] = [];
    if (preferred.length > 0) {
      out.push(preferred);
    }
    if (out.indexOf(image.sourceUrl) < 0) {
      out.push(image.sourceUrl);
    }
    if (out.indexOf(raw) < 0) {
      out.push(raw);
    }
    return out;
  }

  /** Candidate ordering per VideoPreference, with sourceUrl as final fallback. */
  static videoUrls(video: ResolvedVideo, preference: VideoPreference): string[] {
    const sorted = video.candidates.slice(0).sort((a, b): number => {
      const wm = Number(a.watermarked) - Number(b.watermarked);
      if (wm !== 0) {
        return wm;
      }
      const aCompat = a.codec.toLowerCase() === 'h264' || a.codec.toLowerCase() === 'avc' || a.codec.toLowerCase() === 'avc1';
      const bCompat = b.codec.toLowerCase() === 'h264' || b.codec.toLowerCase() === 'avc' || b.codec.toLowerCase() === 'avc1';
      if (preference === VideoPreference.COMPATIBILITY) {
        const c = Number(bCompat) - Number(aCompat);
        if (c !== 0) {
          return c;
        }
      } else {
        const c = Number(b.original) - Number(a.original);
        if (c !== 0) {
          return c;
        }
      }
      let aScore = 0;
      let bScore = 0;
      if (preference === VideoPreference.BITRATE) {
        aScore = a.videoBitrate;
        bScore = b.videoBitrate;
      } else if (preference === VideoPreference.SIZE) {
        aScore = a.size;
        bScore = b.size;
      } else {
        aScore = a.height * a.width;
        bScore = b.height * b.width;
      }
      return bScore - aScore;
    });
    const out: string[] = [];
    for (const c of sorted) {
      if (out.indexOf(c.url) < 0) {
        out.push(c.url);
      }
    }
    if (out.indexOf(video.sourceUrl) < 0) {
      out.push(video.sourceUrl);
    }
    return out;
  }

  /** Filesystem-safe part: control/illegal chars → _, trim, UTF-8 byte cap 160. */
  static safePart(value: string, fallback: string): string {
    let clean = value.replace(/[\u0000-\u001f\\/:*?"<>|]/g, '_').trim();
    while (clean.length > 0 && clean[0] === '.') {
      clean = clean.substring(1);
    }
    while (clean.length > 0 && clean[clean.length - 1] === '.') {
      clean = clean.substring(0, clean.length - 1);
    }
    if (clean.length === 0) {
      clean = fallback;
    }
    let bytes = 0;
    let result = '';
    for (let i = 0; i < clean.length; i++) {
      const code = clean.codePointAt(i) as number;
      let charBytes = 1;
      if (code > 0x7f) {
        charBytes = code > 0x7ff ? (code > 0xffff ? 4 : 3) : 2;
      }
      if (code > 0xffff) {
        i++;
      }
      if (bytes + charBytes > 160) {
        break;
      }
      bytes += charBytes;
      result += String.fromCodePoint(code);
    }
    return result.length > 0 ? result : fallback;
  }

  static pad2(value: number): string {
    return value < 10 ? '0' + String(value) : String(value);
  }

  /** Template render + zero-padded index suffix, byte-capped. */
  static fileName(note: ResolvedNote, settings: AppSettings, index: number, extension: string, createdAt: number): string {
    const date = note.publishedAt > 0 ? NoteOutput.formatTime(note.publishedAt) : note.publishTime;
    const template = settings.useCustomNamingFormat ? settings.customNamingTemplate : '{postId}';
    const values: Record<string, string> = {
      'username': note.authorName,
      'userId': note.authorId,
      'title': note.title,
      'postId': note.noteId,
      'publishTime': date,
      'index': String(index + 1),
      'index_padded': NoteOutput.pad2(index + 1),
      'downloadTimestamp': String(createdAt)
    };
    const base = template.replace(/\{([a-zA-Z_]+)\}/g, (match: string, key: string): string => {
      const v = values[key];
      return v === undefined ? '' : v;
    });
    return NoteOutput.safePart(base, note.noteId.length > 0 ? note.noteId : 'note') +
      '_' + NoteOutput.pad2(index + 1) + '.' + extension;
  }

  /** Stable skip-dedup fingerprint (identical composition to Android recordKey). */
  static recordKey(noteId: string, mediaId: string, settings: AppSettings, folders: string[]): string {
    const o = settings.downloadOptions;
    const identity: string[] = [
      noteId, mediaId, settings.customStorageUri === null ? '' : settings.customStorageUri,
      settings.useCustomNamingFormat ? settings.customNamingTemplate : '{postId}',
      o.imageFormat === ImageFormat.AUTO ? 'AUTO' : (o.imageFormat === ImageFormat.JPEG ? 'JPEG' : (o.imageFormat === ImageFormat.PNG ? 'PNG' : 'WEBP')),
      o.videoPreference === VideoPreference.RESOLUTION ? 'RESOLUTION' : (o.videoPreference === VideoPreference.BITRATE ? 'BITRATE' : (o.videoPreference === VideoPreference.SIZE ? 'SIZE' : 'COMPATIBILITY')),
      o.livePhotoMode === LivePhotoMode.MERGED ? 'MERGED' : (o.livePhotoMode === LivePhotoMode.SEPARATE ? 'SEPARATE' : 'STILL'),
      String(o.livePhotoFormat),
      String(o.imageDownload), String(o.videoDownload), String(o.videoCoverDownload), String(o.writePublishTime)
    ].concat(folders);
    return Sha256.digestHex(JSON.stringify(identity));
  }

  static folders(note: ResolvedNote, options: DownloadOptions, remark: string): string[] {
    const out: string[] = [];
    if (options.authorArchive) {
      const author = remark.length > 0 ? remark : note.authorName;
      out.push(NoteOutput.safePart(author + '_' + note.authorId, 'author'));
    }
    if (options.noteArchive) {
      out.push(NoteOutput.safePart(note.title + '_' + note.noteId, 'note'));
    }
    return out;
  }

  /** Note text export template (markdown/plain), identical to Android. */
  static text(note: ResolvedNote, markdown: boolean): string {
    let out = '';
    out += (markdown ? '# ' : '') + note.title + '\n\n';
    out += (note.body.length > 0 ? note.body : note.description) + '\n\n';
    out += note.authorName + ' [' + note.authorId + ']\n';
    out += note.publishTime + '\n';
    if (note.tags.length > 0) {
      let tags = '';
      for (const tag of note.tags) {
        tags += (tags.length > 0 ? ' ' : '') + '#' + tag;
      }
      out += tags + '\n';
    }
    out += note.canonicalUrl + '\n';
    return out;
  }

  static formatTime(ms: number): string {
    const d = new Date(ms);
    const p = (n: number): string => (n < 10 ? '0' + String(n) : String(n));
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}_${p(d.getHours())}-${p(d.getMinutes())}-${p(d.getSeconds())}`;
  }
}
