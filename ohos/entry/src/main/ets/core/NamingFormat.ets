/** Ported from utils/NamingFormat.kt + MediaUtils name composition. */
import { NamingFormatDefaults, ResolvedNote } from './models';

export class NamingFormat {
  static render(template: string, note: ResolvedNote, index: number, total: number, kind: string): string {
    let out = template;
    const published = note.publishedAt > 0 ? new Date(note.publishedAt) : null;
    const publishText = published !== null ? NamingFormat.formatTime(published) : note.publishTime;
    const replacements: Array<[string, string]> = [
      [NamingFormatDefaults.TOKEN_USERNAME, note.authorName],
      [NamingFormatDefaults.TOKEN_USER_ID, note.authorId],
      [NamingFormatDefaults.TOKEN_TITLE, note.title.length > 0 ? note.title : note.noteId],
      [NamingFormatDefaults.TOKEN_POST_ID, note.noteId],
      [NamingFormatDefaults.TOKEN_PUBLISH_TIME, publishText],
      [NamingFormatDefaults.TOKEN_INDEX, String(index + 1)],
      [NamingFormatDefaults.TOKEN_INDEX_PADDED, NamingFormat.pad2(total, index + 1)],
      [NamingFormatDefaults.TOKEN_DOWNLOAD_TIMESTAMP, String(Date.now())]
    ];
    for (const pair of replacements) {
      out = out.split(NamingFormatDefaults.placeholder(pair[0])).join(pair[1]);
    }
    return NamingFormat.sanitize(out) + '.' + kind;
  }

  static defaultName(note: ResolvedNote, index: number, total: number, kind: string): string {
    return NamingFormat.render(NamingFormatDefaults.DEFAULT_TEMPLATE, note, index, total, kind);
  }

  static pad2(total: number, value: number): string {
    const width = String(total).length;
    let s = String(value);
    while (s.length < width) {
      s = '0' + s;
    }
    return s;
  }

  /** Strip filesystem-hostile characters, keep CJK/word chars, spaces and dashes. */
  static sanitize(name: string): string {
    let out = name.replace(/[\\/:*?"<>|]/g, ' ');
    out = out.replace(/\s+/g, ' ').trim();
    if (out.length === 0) {
      out = 'note';
    }
    // Keep the tail if the name is extremely long (255 byte cap safety).
    if (out.length > 120) {
      out = out.substring(out.length - 120);
    }
    return out;
  }

  static formatTime(d: Date): string {
    const p = (n: number): string => (n < 10 ? '0' + n : String(n));
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
  }
}
