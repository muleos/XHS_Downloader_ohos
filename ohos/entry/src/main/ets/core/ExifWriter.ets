/**
 * JPEG APP1 EXIF segment builder — replaces android.media.ExifInterface for the
 * two attributes the live-photo flow needs: Orientation (0x0112) and
 * UserComment (0x9286). The converted JPEG has no EXIF, so a fresh segment is
 * always inserted right after SOI.
 */
import { ByteWriter } from './ByteReader';

export class ExifWriter {
  /** Insert (or replace the existing APP1 Exif) with fresh tags. */
  static insert(jpeg: Uint8Array, orientation: number, userComment: string): Uint8Array {
    if (jpeg[0] !== 0xff || jpeg[1] !== 0xd8) {
      throw new Error('Missing JPEG SOI');
    }
    let insertAt = 2;
    // Skip any existing APP1 Exif segments so readers see exactly one.
    let pos = 2;
    while (pos + 4 <= jpeg.length && jpeg[pos] === 0xff && (jpeg[pos + 1] & 0xff) === 0xe1) {
      const size = ((jpeg[pos + 2] & 0xff) << 8) | (jpeg[pos + 3] & 0xff);
      const head = ExifWriter.asciiAt(jpeg, pos + 4, 6);
      if (head !== 'Exif\u0000\u0000') {
        break;
      }
      pos += 2 + size;
      insertAt = pos;
    }
    if (pos > insertAt) {
      // Existing exif found: rebuild without it (converted JPEGs carry none anyway).
      const without = new Uint8Array(jpeg.length - (insertAt - 2));
      without.set(jpeg.slice(0, 2), 0);
      without.set(jpeg.slice(insertAt), 2);
      return ExifWriter.insertFresh(without, orientation, userComment);
    }
    return ExifWriter.insertFresh(jpeg, orientation, userComment);
  }

  private static insertFresh(jpeg: Uint8Array, orientation: number, userComment: string): Uint8Array {
    const comment = ExifWriter.utf8(userComment);
    const commentData = ExifWriter.ascii('ASCII\u0000\u0000\u0000').concat(Array.from(comment));
    // IFD0: 2 entries (Orientation SHORT, UserComment UNDEFINED).
    const ifdSize = 2 + 2 * 12 + 4;
    const dataStart = 8 + ifdSize; // tiff header + IFD
    const commentOffset = dataStart;
    const tiffSize = dataStart + commentData.length;
    const w = new ByteWriter();
    // APP1 marker + length + "Exif\0\0" + TIFF (little endian).
    w.writeByte(0xff).writeByte(0xe1).writeShort(tiffSize + 8);
    w.writeAscii('Exif\u0000\u0000');
    w.writeAscii('II').writeShort(42).writeInt(8);
    // IFD0
    w.writeShort(2);
    // Orientation: tag 0x0112, type 3 (SHORT), count 1, value in low bytes.
    w.writeShort(0x0112).writeShort(3).writeInt(1).writeShort(orientation).writeShort(0);
    // UserComment: tag 0x9286, type 7 (UNDEFINED), count = data len, offset.
    w.writeShort(0x9286).writeShort(7).writeInt(commentData.length).writeInt(commentOffset);
    w.writeInt(0); // next IFD
    for (const b of commentData) {
      w.writeByte(b);
    }
    const app1 = w.toUint8();
    if (app1.length > 65535) {
      throw new Error('EXIF segment too large');
    }
    const out = new Uint8Array(2 + app1.length + jpeg.length - 2);
    out.set(jpeg.slice(0, 2), 0);
    out.set(app1, 2);
    out.set(jpeg.slice(2), 2 + app1.length);
    return out;
  }

  private static asciiAt(bytes: Uint8Array, start: number, size: number): string {
    let s = '';
    for (let i = start; i < start + size && i < bytes.length; i++) {
      s += String.fromCharCode(bytes[i] & 0xff);
    }
    return s;
  }

  private static ascii(text: string): number[] {
    const out: number[] = [];
    for (let i = 0; i < text.length; i++) {
      out.push(text.charCodeAt(i) & 0xff);
    }
    return out;
  }

  private static utf8(text: string): Uint8Array {
    const w = new ByteWriter();
    w.writeAscii(text);
    return w.toUint8();
  }
}
