/** Port of data/account/WebAccountRepository.kt — display metadata only. */
import { fileIo } from '@kit.CoreFileKit';
import { Context } from '@kit.AbilityKit';

export class WebAccount {
  userId: string;
  nickname: string;
  avatar: string;

  constructor(userId: string, nickname: string, avatar: string) {
    this.userId = userId;
    this.nickname = nickname;
    this.avatar = avatar;
  }
}

export class XhsWebSession {
  static readonly HOME: string = 'https://www.xiaohongshu.com/explore';

  static isTrusted(url: string): boolean {
    if (url === null || url === undefined) {
      return false;
    }
    const match = url.match(/^https:\/\/([^/?#]+)/i);
    if (match === null) {
      return false;
    }
    const host = match[1].toLowerCase();
    return host === 'xiaohongshu.com' || host === 'www.xiaohongshu.com' ||
      host === 'rednote.com' || host === 'www.rednote.com';
  }

  static desktopUserAgent(defaultUa: string): string {
    return defaultUa.replace(/\([^)]*\)/, '(X11; Linux x86_64)')
      .replace(' Version/4.0', '').replace(' Mobile', '');
  }
}

type AccountListener = (account: WebAccount | null) => void;

export class WebAccountRepository {
  private file: string = '';
  private account: WebAccount | null = null;
  private listeners: AccountListener[] = [];

  async init(context: Context): Promise<void> {
    this.file = context.filesDir + '/web-account.json';
    try {
      const stat = fileIo.statSync(this.file);
      const f = fileIo.openSync(this.file, fileIo.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(f.fd, buf);
      fileIo.closeSync(f.fd);
      this.account = WebAccountRepository.parse(String(buf));
    } catch (e) {
      this.account = null;
    }
  }

  get(): WebAccount | null {
    return this.account;
  }

  onChange(listener: AccountListener): void {
    this.listeners.push(listener);
  }

  /** Input from xhs_account.js; invalid payloads clear the stored account. */
  async update(raw: string): Promise<void> {
    this.account = WebAccountRepository.parse(raw);
    try {
      const f = fileIo.openSync(this.file, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, this.account === null ? '{}' : JSON.stringify({
        'userId': this.account.userId, 'nickname': this.account.nickname, 'avatar': this.account.avatar
      }));
      fileIo.closeSync(f.fd);
    } catch (e) {
    }
    for (const listener of this.listeners) {
      listener(this.account);
    }
  }

  private static parse(raw: string): WebAccount | null {
    try {
      const obj = JSON.parse(raw) as Record<string, Object>;
      const id = String(obj['userId'] ?? '');
      if (!/^[a-fA-F0-9]{24}$/.test(id)) {
        return null;
      }
      const avatar = String(obj['avatar'] ?? '');
      if (avatar.length > 0 && !avatar.startsWith('https://')) {
        return new WebAccount(id, String(obj['nickname'] ?? '').substring(0, 200), '');
      }
      return new WebAccount(id, String(obj['nickname'] ?? '').substring(0, 200), avatar);
    } catch (e) {
      return null;
    }
  }
}
