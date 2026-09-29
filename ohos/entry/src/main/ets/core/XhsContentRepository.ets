/** Ported from data/xhs/XhsContentRepository.kt — resolve orchestration. */
import { XhsUrlParser } from './XhsUrlParser';
import { ParsedXhsNote, XhsNoteParser } from './XhsNoteParser';
import { XhsHttpClient } from './XhsHttpClient';
import { ResolvedNote } from './models';

export enum ResolveFailure {
  NETWORK = 0,
  NOT_NOTE = 1,
  NO_MEDIA = 2,
  PARSE_FAILED = 3
}

export class XhsResolveException extends Error {
  failure: ResolveFailure;

  constructor(failure: ResolveFailure, detail: string = '') {
    super(detail.length > 0 ? detail : 'resolve failure ' + failure);
    this.failure = failure;
  }
}

export class XhsContentRepository {
  private client: XhsHttpClient;

  constructor(client: XhsHttpClient) {
    this.client = client;
  }

  /** Resolve one share text (may contain extra prose) into a note snapshot. */
  async resolve(rawInput: string, useWebSession: boolean, timeoutSeconds: number): Promise<ResolvedNote> {
    const links = XhsUrlParser.extractLinks(rawInput);
    if (links.length === 0) {
      throw new XhsResolveException(ResolveFailure.NOT_NOTE, 'no link in input');
    }
    const firstUrl = links[0];
    const short = XhsUrlParser.isShortUrl(firstUrl);
    let expectedNoteId = XhsUrlParser.extractPostId(firstUrl);
    let canonicalUrl = firstUrl;
    let html = '';
    try {
      html = await this.client.fetchHtml(firstUrl, useWebSession, timeoutSeconds);
    } catch (e) {
      throw new XhsResolveException(ResolveFailure.NETWORK, e instanceof Error ? e.message : String(e));
    }
    if (short) {
      // Redirect chain already followed; parse the returned page directly.
      expectedNoteId = '';
    }
    const parser = new XhsNoteParser();
    const parsed: ParsedXhsNote = parser.parse(html, expectedNoteId, canonicalUrl);
    if (parsed.resolved === null) {
      if (parsed.mediaUrls.length === 0) {
        throw new XhsResolveException(ResolveFailure.PARSE_FAILED, 'state not found');
      }
      // Legacy fallback resolved plain media urls only.
      const legacy = new ResolvedNote();
      legacy.canonicalUrl = canonicalUrl;
      return legacy;
    }
    if (parsed.resolved.items.length === 0 && parsed.resolved.body.length === 0 &&
      parsed.resolved.title.length === 0) {
      throw new XhsResolveException(ResolveFailure.NO_MEDIA, 'empty note');
    }
    return parsed.resolved;
  }
}
