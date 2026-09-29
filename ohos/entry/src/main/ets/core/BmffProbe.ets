/**
 * Pure-TS ISO-BMFF (MP4/MOV) inspector — replaces Android MediaExtractor in
 * inspectTracks(): track mimes, duration and video frame count (stsz samples),
 * plus the size-zero trailing box fixup used by the vivo pair flow.
 */
import { ByteReader } from './ByteReader';

export class VideoTracks {
  mimeTypes: string[] = [];
  durationMs: number = 0;
  frameCount: number = 0;

  equals(other: VideoTracks): boolean {
    if (this.mimeTypes.length !== other.mimeTypes.length || this.durationMs !== other.durationMs) {
      return false;
    }
    for (let i = 0; i < this.mimeTypes.length; i++) {
      if (this.mimeTypes[i] !== other.mimeTypes[i]) {
        return false;
      }
    }
    return true;
  }
}

function mimeFromCodec(type: string): string {
  if (type === 'avc1' || type === 'avc3') {
    return 'video/avc';
  }
  if (type === 'hvc1' || type === 'hev1') {
    return 'video/hevc';
  }
  if (type === 'mp4a') {
    return 'audio/mp4a-latm';
  }
  if (type === 'Opus') {
    return 'audio/opus';
  }
  return type;
}

function codecOfTrack(r: ByteReader, boxStart: number, boxEnd: number): string {
  // Walk mdia -> minf -> stbl -> stsd; first child entry is the codec box.
  let depth: Array<[number, number, string]> = [[boxStart, boxEnd, '']];
  let codec = '';
  while (depth.length > 0 && codec.length === 0) {
    const frame = depth.pop() as [number, number, string];
    let pos = frame[0];
    const end = frame[1];
    const container = frame[2];
    while (pos + 8 <= end) {
      let size = r.u32U(pos);
      const type = r.ascii(pos + 4, 4);
      let header = 8;
      if (size === 1) {
        // 64-bit extended size (rare); approximate with boxEnd.
        size = end - pos;
        header = 16;
      } else if (size === 0) {
        size = end - pos;
      }
      if (size < header || pos + size > end) {
        break;
      }
      if (container === 'stsd' && size > 8) {
        codec = type;
        break;
      }
      if (type === 'moov' || type === 'trak' || type === 'mdia' || type === 'minf' ||
        type === 'stbl' || type === 'stsd') {
        depth.push([pos + header, pos + size, type]);
      }
      pos += size;
    }
  }
  return codec;
}

export class BmffProbe {
  /** Inspect tracks inside [offset, offset+length) — inspectTracks() parity. */
  static inspect(bytes: Uint8Array, offset: number, length: number, countFrames: boolean = false): VideoTracks {
    return BmffProbe.inspectTracks(new ByteReader(bytes), offset, length, countFrames);
  }

  static frameCount(bytes: Uint8Array, offset: number, length: number): number {
    return BmffProbe.inspectTracks(new ByteReader(bytes), offset, length, true).frameCount;
  }

  static inspectTracks(r: ByteReader, offset: number, length: number, countFrames: boolean = false): VideoTracks {
    const out = new VideoTracks();
    let pos = offset;
    const end = Math.min(offset + length, r.length);
    // Walk top-level boxes; remember moov ranges.
    const moovs: Array<[number, number]> = [];
    while (pos + 8 <= end) {
      let size = r.u32U(pos);
      const type = r.ascii(pos + 4, 4);
      let header = 8;
      if (size === 1) {
        if (end - pos < 16) {
          break;
        }
        const hi = r.u32U(pos + 8);
        const lo = r.u32U(pos + 12);
        size = hi * 0x100000000 + lo;
        header = 16;
      } else if (size === 0) {
        size = end - pos;
      }
      if (size < header || pos + size > end) {
        break;
      }
      if (type === 'moov') {
        moovs.push([pos + header, pos + size]);
      }
      pos += size;
    }
    for (const moov of moovs) {
      BmffProbe.walkTraks(r, moov[0], moov[1], countFrames, out);
    }
    let hasVideo = false;
    for (const mime of out.mimeTypes) {
      if (mime.startsWith('video/')) {
        hasVideo = true;
      }
    }
    if (!hasVideo) {
      throw new Error('No readable video track');
    }
    return out;
  }

  private static walkTraks(r: ByteReader, start: number, end: number, countFrames: boolean, out: VideoTracks): void {
    let pos = start;
    while (pos + 8 <= end) {
      let size = r.u32U(pos);
      const type = r.ascii(pos + 4, 4);
      let header = 8;
      if (size === 1) {
        const hi = r.u32U(pos + 8);
        const lo = r.u32U(pos + 12);
        size = hi * 0x100000000 + lo;
        header = 16;
      } else if (size === 0) {
        size = end - pos;
      }
      if (size < header || pos + size > end) {
        break;
      }
      if (type === 'trak') {
        BmffProbe.parseTrak(r, pos + header, pos + size, countFrames, out);
      }
      pos += size;
    }
  }

  private static parseTrak(r: ByteReader, start: number, end: number, countFrames: boolean, out: VideoTracks): void {
    let codec = '';
    let isVideo = false;
    let isAudio = false;
    let durationMs = 0;
    let frameCount = 0;
    // mdhd duration + hdlr type + stbl stsz count + stsd codec.
    let pos = start;
    while (pos + 8 <= end) {
      let size = r.u32U(pos);
      const type = r.ascii(pos + 4, 4);
      let header = 8;
      if (size === 1) {
        const hi = r.u32U(pos + 8);
        const lo = r.u32U(pos + 12);
        size = hi * 0x100000000 + lo;
        header = 16;
      } else if (size === 0) {
        size = end - pos;
      }
      if (size < header || pos + size > end) {
        break;
      }
      const body = pos + header;
      if (type === 'hdlr' && size >= header + 8) {
        const handler = r.ascii(body + 8, 4);
        isVideo = handler === 'vide';
        isAudio = handler === 'soun';
      } else if (type === 'mdhd' && size >= header + 4) {
        const version = r.u8(body);
        if (version === 1) {
          const timescale = r.u32U(body + 20);
          const durHi = r.u32U(body + 24);
          const durLo = r.u32U(body + 28);
          if (timescale > 0) {
            durationMs = ((durHi * 0x100000000) + durLo) * 1000 / timescale;
          }
        } else {
          const timescale = r.u32U(body + 12);
          const duration = r.u32U(body + 16);
          if (timescale > 0) {
            durationMs = duration * 1000 / timescale;
          }
        }
      } else if (type === 'stbl') {
        codec = codecOfTrack(r, body, pos + size);
        // stsz: sample_count at body+8.
        let sp = body;
        while (sp + 8 <= pos + size) {
          let ssize = r.u32U(sp);
          const stype = r.ascii(sp + 4, 4);
          let sheader = 8;
          if (ssize === 1) {
            ssize = pos + size - sp;
            sheader = 16;
          } else if (ssize === 0) {
            ssize = pos + size - sp;
          }
          if (ssize < sheader || sp + ssize > pos + size) {
            break;
          }
          if (stype === 'stsz' && ssize >= sheader + 8) {
            frameCount = r.u32U(sp + sheader + 4);
          }
          sp += ssize;
        }
      }
      pos += size;
    }
    if (!isVideo && !isAudio) {
      return;
    }
    if (codec.length === 0) {
      return;
    }
    const mime = mimeFromCodec(codec);
    out.mimeTypes.push(mime);
    if (isVideo) {
      if (frameCount <= 0) {
        throw new Error('Empty media track');
      }
      if (durationMs > out.durationMs) {
        out.durationMs = durationMs;
      }
      if (countFrames) {
        out.frameCount = frameCount;
      }
    }
  }

  /** Terminate a size-zero final box so a trailing uuid box can be appended (vivo pair). */
  static fixZeroTerminator(r: ByteReader): boolean {
    let pos = 0;
    while (pos + 8 <= r.length) {
      let size = r.u32U(pos);
      let header = 8;
      if (size === 1) {
        if (r.length - pos < 16) {
          return false;
        }
        const hi = r.u32U(pos + 8);
        const lo = r.u32U(pos + 12);
        size = hi * 0x100000000 + lo;
        header = 16;
      } else if (size === 0) {
        const remaining = r.length - pos;
        if (remaining > 0xffffffff) {
          throw new Error('Video box is too large');
        }
        r.bytes[pos] = (remaining >>> 24) & 0xff;
        r.bytes[pos + 1] = (remaining >>> 16) & 0xff;
        r.bytes[pos + 2] = (remaining >>> 8) & 0xff;
        r.bytes[pos + 3] = remaining & 0xff;
        return true;
      }
      if (size < header) {
        return false;
      }
      pos += size;
    }
    return false;
  }
}
