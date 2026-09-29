/**
 * Ported from data/network/XhsNetwork.kt (client part) — UA suffix
 * "xiaohongshu", per-host web-session cookie injection, timeouts.
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

export class XhsHttpClient {
  /** Same UA as the Android client: mobile Chrome with the xiaohongshu suffix. */
  static readonly USER_AGENT: string =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36 xiaohongshu';

  static readonly COOKIE_HOSTS: string[] = ['www.xiaohongshu.com', 'www.rednote.com'];

  private sessionStore: preferences.Preferences | null = null;

  async initSessionStore(context: Context): Promise<void> {
    try {
      this.sessionStore = await preferences.getPreferences(context, 'web_session');
    } catch (e) {
      this.sessionStore = null;
    }
  }

  /** Manual session wins over the WebView cookie jar, mirroring the Android client. */
  getCookieForHost(host: string, useWebSession: boolean): string {
    if (this.sessionStore !== null) {
      const manual = this.sessionStore.getSync('cookie_' + host, '') as string;
      if (manual !== null && manual.length > 0) {
        return manual;
      }
    }
    if (useWebSession) {
      try {
        const cookie = webview.WebCookieManager.fetchCookieSync('https://' + host);
        return cookie !== undefined ? cookie : '';
      } catch (e) {
        return '';
      }
    }
    return '';
  }

  async saveManualCookie(host: string, cookie: string): Promise<void> {
    if (this.sessionStore === null) {
      return;
    }
    await this.sessionStore.put('cookie_' + host, cookie);
    await this.sessionStore.flush();
  }

  async clearManualCookies(): Promise<void> {
    if (this.sessionStore === null) {
      return;
    }
    for (const host of XhsHttpClient.COOKIE_HOSTS) {
      await this.sessionStore.delete('cookie_' + host);
    }
    await this.sessionStore.flush();
  }

  hasManualCookie(): boolean {
    if (this.sessionStore === null) {
      return false;
    }
    for (const host of XhsHttpClient.COOKIE_HOSTS) {
      const value = this.sessionStore.getSync('cookie_' + host, '') as string;
      if (value !== null && value.length > 0) {
        return true;
      }
    }
    return false;
  }

  /** Cookie header for an arbitrary target URL; only sent over HTTPS like the Android client. */
  cookieHeaderFor(targetUrl: string, useWebSession: boolean): string {
    if (!targetUrl.startsWith('https://')) {
      return '';
    }
    for (const host of XhsHttpClient.COOKIE_HOSTS) {
      if (targetUrl.includes(host)) {
        return this.getCookieForHost(host, useWebSession);
      }
    }
    return '';
  }

  /** Fetch a page as text following redirects (ohos http follows 3xx by default). */
  fetchHtml(url: string, useWebSession: boolean, timeoutSeconds: number): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void, reject: (e: Error) => void) => {
      const client = http.createHttp();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': XhsHttpClient.USER_AGENT,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9'
        } as Record<string, string>,
        connectTimeout: Math.max(5, timeoutSeconds) * 1000,
        readTimeout: Math.max(5, timeoutSeconds) * 1000,
        usingCache: false
      };
      const cookie = this.cookieHeaderFor(url, useWebSession);
      if (cookie.length > 0) {
        (options.header as Record<string, string>)['Cookie'] = cookie;
      }
      client.request(url, options).then((response: http.HttpResponse) => {
        const code = response.responseCode;
        const text = typeof response.result === 'string' ? response.result as string : '';
        client.destroy();
        if (code >= 200 && code < 400 && text.length > 0) {
          resolve(text);
        } else {
          reject(new Error('HTTP ' + code));
        }
      }).catch((e: BusinessError) => {
        client.destroy();
        reject(new Error(e.message !== undefined ? e.message : 'network error'));
      });
    });
  }

  /** Resolve a short link to its final location via a HEAD-ish GET on the final page. */
  async resolveShortLink(shortUrl: string, useWebSession: boolean, timeoutSeconds: number): Promise<string> {
    try {
      return await this.fetchHtml(shortUrl, useWebSession, timeoutSeconds);
    } catch (e) {
      return '';
    }
  }
}
