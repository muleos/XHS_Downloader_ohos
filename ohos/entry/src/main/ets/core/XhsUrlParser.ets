/** Ported from data/xhs/XhsUrlParser.kt */
export class XhsUrlParser {
  private static readonly LINK_REGEX: RegExp =
    /(?:https?:\/\/)?(?:www\.)?(?:xiaohongshu\.com|rednote\.com|xhslink\.(?:com|cn))[^\s"<>"\\^`{|}，。；！？、【】《》]+/gi;

  private static readonly HOSTS: string[] = [
    'xiaohongshu.com', 'www.xiaohongshu.com', 'rednote.com', 'www.rednote.com',
    'xhslink.com', 'xhslink.cn'
  ];

  private static readonly SHORT_HOSTS: string[] = ['xhslink.com', 'xhslink.cn'];

  /** Extract candidate links from free-form share text. */
  static extractLinks(input: string): string[] {
    const out: string[] = [];
    if (input === null || input.length === 0) {
      return out;
    }
    const regex = new RegExp(XhsUrlParser.LINK_REGEX.source, 'gi');
    let match: RegExpExecArray | null = regex.exec(input);
    while (match !== null) {
      const start = match.index;
      const raw0 = match[0];
      const preceding = start > 0 ? input[start - 1] : '';
      const isWordish = (preceding >= 'a' && preceding <= 'z') ||
        (preceding >= 'A' && preceding <= 'Z') || (preceding >= '0' && preceding <= '9') ||
        preceding === '.' || preceding === '_' || preceding === '-';
      if (!isWordish) {
        out.push(XhsUrlParser.trimTrailingJunk(raw0));
      }
      match = regex.exec(input);
    }
    return out;
  }

  private static trimTrailingJunk(raw: string): string {
    let end = raw.length;
    const junk = ')]}.,;!，。）】';
    while (end > 0 && junk.indexOf(raw[end - 1]) >= 0) {
      end--;
    }
    return raw.substring(0, end);
  }

  static normalizeUrl(url: string): string {
    const trimmed = url.trim();
    if (trimmed.length === 0) {
      return '';
    }
    const lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }
    return 'https://' + trimmed;
  }

  static hostOf(url: string): string {
    const normalized = XhsUrlParser.normalizeUrl(url);
    const match = normalized.match(/^https?:\/\/([^/?#]+)/i);
    if (match === null) {
      return '';
    }
    return match[1].toLowerCase();
  }

  static isSupportedUrl(url: string): boolean {
    const host = XhsUrlParser.hostOf(url);
    return XhsUrlParser.HOSTS.indexOf(host) >= 0;
  }

  static isShortUrl(url: string): boolean {
    const host = XhsUrlParser.hostOf(url);
    return XhsUrlParser.SHORT_HOSTS.indexOf(host) >= 0;
  }

  static extractPostId(url: string): string {
    if (url === null || url.length === 0) {
      return '';
    }
    const normalized = XhsUrlParser.normalizeUrl(url);
    if (!XhsUrlParser.isSupportedUrl(normalized) || XhsUrlParser.isShortUrl(normalized)) {
      return '';
    }
    const pathMatch = normalized.match(/^https?:\/\/[^/?#]+(\/[^?#]*)/i);
    if (pathMatch === null) {
      return '';
    }
    const path = pathMatch[1].replace(/^\/+/, '').replace(/\/+$/, '');
    const segments = path.split('/');
    if (segments.length === 2 && segments[0] === 'explore') {
      return XhsUrlParser.validId(segments[1]);
    }
    if (segments.length === 3 && segments[0] === 'discovery' && segments[1] === 'item') {
      return XhsUrlParser.validId(segments[2]);
    }
    if (segments.length === 4 && segments[0] === 'user' && segments[1] === 'profile') {
      return XhsUrlParser.validId(segments[3]);
    }
    return '';
  }

  private static validId(value: string): string {
    return /^[A-Za-z0-9_-]+$/.test(value) ? value : '';
  }
}
