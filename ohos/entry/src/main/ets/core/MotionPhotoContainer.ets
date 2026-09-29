/**
 * Ported from MotionPhotoContainer.kt — binary layout only, byte-exact.
 * STANDARD/XIAOMI (XMP GContainer), OPLUS (MPF + tail), SAMSUNG (SEFT),
 * VIVO (uuid vivoMediaExtInfo), HUAWEI (v6_f0 tail).
 */
import { LivePhotoFormat } from './models';
import { ByteWriter, ByteReader } from './ByteReader';

export class ContainerLayout {
  videoOffset: number;
  videoLength: number;
  totalLength: number;
  imageSize: number = 0;

  constructor(videoOffset: number, videoLength: number, totalLength: number) {
    this.videoOffset = videoOffset;
    this.videoLength = videoLength;
    this.totalLength = totalLength;
  }
}

export class MotionPhotoContainer {
  /** Assembles the container into `output` bytes; returns the layout. */
  static write(jpeg: Uint8Array, video: Uint8Array, format: LivePhotoFormat, videoMime: string,
    videoFrameCount: number): ContainerLayout {
    if (format === LivePhotoFormat.AUTO || format === LivePhotoFormat.VIVO_LEGACY) {
      throw new Error('Format requires resolution before container assembly');
    }
    if (video.length === 0) {
      throw new Error('Empty video');
    }
    const prefix = format === LivePhotoFormat.SAMSUNG ?
      MotionPhotoContainer.samsungTag(0x0a30, 'MotionPhoto_Data') : new Uint8Array(0);
    const suffix = format === LivePhotoFormat.SAMSUNG ?
      MotionPhotoContainer.samsungFooter(video.length, prefix.length) :
      format === LivePhotoFormat.HUAWEI ? MotionPhotoContainer.huaweiTail(video.length, videoFrameCount) :
        new Uint8Array(0);
    const xmp = format === LivePhotoFormat.HUAWEI ? new Uint8Array(0) :
      MotionPhotoContainer.segment(0xe1, MotionPhotoContainer.asciiBytes(
        'http://ns.adobe.com/xap/1.0/\u0000' +
        MotionPhotoContainer.xmp(format, video.length + suffix.length, prefix.length, videoMime)));
    const mpfSize = format === LivePhotoFormat.OPLUS ? MotionPhotoContainer.mpf(0).length : 0;
    const imageSize = jpeg.length + xmp.length + mpfSize;
    const layout = new ContainerLayout(imageSize + prefix.length, video.length,
      imageSize + prefix.length + video.length + suffix.length);

    const out = new ByteWriter();
    if (jpeg[0] !== 0xff || jpeg[1] !== 0xd8) {
      throw new Error('Missing JPEG SOI');
    }
    out.writeByte(0xff).writeByte(0xd8);
    // Xiaomi retains the SOI -> XMP -> JPEG layout of the previously working writer.
    if (format !== LivePhotoFormat.XIAOMI) {
      out.writeBytes(MotionPhotoContainer.copyLeadingMetadata(jpeg));
    }
    out.writeBytes(xmp);
    if (mpfSize > 0) {
      out.writeBytes(MotionPhotoContainer.mpf(imageSize));
    }
    // JPEG body minus the copied leading metadata and SOI, up to and including EOI.
    const metaEnd = jpeg.length - MotionPhotoContainer.trailingAfterMetadata(jpeg);
    for (let i = 2; i < metaEnd; i++) {
      out.writeByte(jpeg[i]);
    }
    out.writeBytes(prefix);
    out.writeBytes(video);
    out.writeBytes(suffix);

    const result = out.toUint8();
    if (result.length !== layout.totalLength) {
      throw new Error('Motion photo length mismatch');
    }
    // Verify EOI before video and ftyp at video offset.
    const reader = new ByteReader(result);
    if (reader.u16(layout.imageSize - 2) !== 0xffd9) {
      throw new Error('Missing JPEG EOI before video');
    }
    const vftyp = reader.ascii(layout.videoOffset + 4, 4);
    if (vftyp !== 'ftyp') {
      throw new Error('Missing video at declared offset');
    }
    MotionPhotoContainer.lastOutput = result;
    MotionPhotoContainer.lastLayout = layout;
    return layout;
  }

  static lastOutput: Uint8Array = new Uint8Array(0);
  static lastLayout: ContainerLayout | null = null;

  /** Bytes after the leading APPn metadata block (marker walk parity). */
  private static trailingAfterMetadata(jpeg: Uint8Array): number {
    // Walk from position 2; return number of bytes NOT consumed by leading metadata.
    let pos = 2;
    while (pos + 4 <= jpeg.length) {
      if (jpeg[pos] !== 0xff) {
        throw new Error('Invalid JPEG marker');
      }
      const marker = jpeg[pos + 1] & 0xff;
      if (marker < 0xe0 || marker > 0xef) {
        break;
      }
      const length = ((jpeg[pos + 2] & 0xff) << 8) | (jpeg[pos + 3] & 0xff);
      if (length < 2) {
        throw new Error('Invalid JPEG segment');
      }
      pos += 2 + length;
    }
    return jpeg.length - pos;
  }

  private static copyLeadingMetadata(jpeg: Uint8Array): Uint8Array {
    const consumed = MotionPhotoContainer.trailingAfterMetadata(jpeg);
    return jpeg.slice(0, jpeg.length - consumed);
  }

  /** Reject truncated ISO-BMFF data and detect MOV without trusting its extension. */
  static videoMime(video: Uint8Array): string {
    const r = new ByteReader(video);
    let position = 0;
    let mime = 'video/mp4';
    let hasMovie = false;
    let hasData = false;
    while (position < video.length) {
      if (video.length - position < 8) {
        throw new Error('Truncated video box');
      }
      let size = r.u32U(position);
      const type = r.ascii(position + 4, 4);
      let headerSize = 8;
      if (size === 1) {
        if (video.length - position < 16) {
          throw new Error('Truncated extended video box');
        }
        const hi = r.u32U(position + 8);
        const lo = r.u32U(position + 12);
        size = hi * 0x100000000 + lo;
        headerSize = 16;
      } else if (size === 0) {
        size = video.length - position;
      }
      if (size < headerSize || size > video.length - position) {
        throw new Error('Invalid video box size');
      }
      if (position === 0) {
        if (type !== 'ftyp' || size < headerSize + 8) {
          throw new Error('Missing video file type');
        }
        if (r.ascii(position + 8, 4) === 'qt  ') {
          mime = 'video/quicktime';
        }
      }
      if (type === 'moov') {
        hasMovie = size > headerSize;
      }
      if (type === 'mdat') {
        hasData = hasData || size > headerSize;
      }
      position += size;
    }
    if (!hasMovie || !hasData) {
      throw new Error('Video has no movie or media data');
    }
    return mime;
  }

  static xmp(format: LivePhotoFormat, videoLength: number, padding: number, mime: string): string {
    if (videoLength <= 0 || padding < 0) {
      throw new Error('Invalid xmp parameters');
    }
    if (mime !== 'video/mp4' && mime !== 'video/quicktime') {
      throw new Error('Unsupported video mime');
    }
    if (format === LivePhotoFormat.XIAOMI) {
      if (padding !== 0) {
        throw new Error('Xiaomi xmp requires zero padding');
      }
      return MotionPhotoContainer.xiaomiXmp(videoLength).split('video/mp4').join(mime);
    }
    let vendor = '';
    if (format === LivePhotoFormat.OPLUS) {
      vendor = 'xmlns:OpCamera="http://ns.oplus.com/photos/1.0/camera/"\n' +
        'OpCamera:MotionPhotoPrimaryPresentationTimestampUs="0"\n' +
        'OpCamera:MotionPhotoOwner="oplus" OpCamera:OLivePhotoVersion="2"\n' +
        `OpCamera:MotionPhotoFeatureFlag="1" OpCamera:VideoLength="${videoLength}"`;
    } else if (format === LivePhotoFormat.VIVO) {
      vendor = 'xmlns:VCamera="http://ns.vivo.com/photos/1.0/camera/"\n' +
        'VCamera:VMotionPhotoVersion="1" VCamera:VMotionPhotoSource="1" VCamera:VMediaKitVersion="1.0.0.9"';
    }
    // Retain the v1 offset for older Google readers. It is measured from EOF.
    const legacy = format === LivePhotoFormat.STANDARD ?
      'GCamera:MicroVideo="1" GCamera:MicroVideoVersion="1"\n' +
      `GCamera:MicroVideoOffset="${videoLength}" GCamera:MicroVideoPresentationTimestampUs="-1"` : '';
    // Match vendor writers' default cover convention; only generic/Samsung use unknown time.
    const timestamp = (format === LivePhotoFormat.OPLUS || format === LivePhotoFormat.VIVO) ? 0 : -1;
    const primaryExtent = format === LivePhotoFormat.VIVO ? '' :
      `Item:Length="0" Item:Padding="${padding}"`;
    return `<x:xmpmeta xmlns:x="adobe:ns:meta/">\n` +
      '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n' +
      '<rdf:Description rdf:about="" xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"\n' +
      ' xmlns:Container="http://ns.google.com/photos/1.0/container/"\n' +
      ' xmlns:Item="http://ns.google.com/photos/1.0/container/item/"\n' +
      ` GCamera:MotionPhoto="1" GCamera:MotionPhotoVersion="1" GCamera:MotionPhotoPresentationTimestampUs="${timestamp}"\n` +
      ` ${vendor} ${legacy}>\n` +
      ' <Container:Directory><rdf:Seq>\n' +
      `  <rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary" ${primaryExtent}/></rdf:li>\n` +
      `  <rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="${mime}" Item:Semantic="MotionPhoto" Item:Length="${videoLength}" Item:Padding="0"/></rdf:li>\n` +
      ' </rdf:Seq></Container:Directory>\n' +
      '</rdf:Description></rdf:RDF></x:xmpmeta>';
  }

  private static xiaomiXmp(videoSize: number): string {
    return `<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 5.1.0-jc003">` +
      `<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">` +
      `<rdf:Description rdf:about=""` +
      `    xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"` +
      `    xmlns:OpCamera="http://ns.oplus.com/photos/1.0/camera/"` +
      `    xmlns:MiCamera="http://ns.xiaomi.com/photos/1.0/camera/"` +
      `    xmlns:Container="http://ns.google.com/photos/1.0/container/"` +
      `    xmlns:Item="http://ns.google.com/photos/1.0/container/item/"` +
      `  GCamera:MotionPhoto="1"` +
      `  GCamera:MotionPhotoVersion="1"` +
      `  GCamera:MotionPhotoPresentationTimestampUs="0"` +
      `  OpCamera:MotionPhotoPrimaryPresentationTimestampUs="0"` +
      `  OpCamera:MotionPhotoOwner="xhs"` +
      `  OpCamera:OLivePhotoVersion="2"` +
      `  OpCamera:VideoLength="${videoSize}"` +
      `  GCamera:MicroVideoVersion="1"` +
      `  GCamera:MicroVideo="1"` +
      `  GCamera:MicroVideoOffset="${videoSize}"` +
      `  GCamera:MicroVideoPresentationTimestampUs="0"` +
      `  MiCamera:XMPMeta="&lt;?xml version='1.0' encoding='UTF-8' standalone='yes' ?&gt;">` +
      `  <Container:Directory>` +
      `    <rdf:Seq>` +
      `      <rdf:li rdf:parseType="Resource">` +
      `        <Container:Item` +
      `          Item:Mime="image/jpeg"` +
      `          Item:Semantic="Primary"` +
      `          Item:Length="0"` +
      `          Item:Padding="0"/>` +
      `      </rdf:li>` +
      `      <rdf:li rdf:parseType="Resource">` +
      `        <Container:Item` +
      `          Item:Mime="video/mp4"` +
      `          Item:Semantic="MotionPhoto"` +
      `          Item:Length="${videoSize}"/>` +
      `      </rdf:li>` +
      `    </rdf:Seq>` +
      `  </Container:Directory>` +
      `</rdf:Description>` +
      `</rdf:RDF>` +
      `</x:xmpmeta>`;
  }

  private static segment(marker: number, data: Uint8Array): Uint8Array {
    if (data.length > 65533) {
      throw new Error('JPEG segment too large');
    }
    return new ByteWriter().writeByte(0xff).writeByte(marker)
      .writeShort(data.length + 2).writeBytes(data).toUint8();
  }

  private static mpf(imageSize: number): Uint8Array {
    return MotionPhotoContainer.segment(0xe2, new ByteWriter()
      .writeAscii('MPF\u0000MM').writeShort(42).writeInt(8).writeShort(3)
      .writeShort(0xb000).writeShort(7).writeInt(4).writeAscii('0100')
      .writeShort(0xb001).writeShort(4).writeInt(1).writeInt(1)
      .writeShort(0xb002).writeShort(7).writeInt(16).writeInt(50)
      .writeInt(0)
      .writeInt(0x00030000).writeInt(imageSize).writeInt(0).writeInt(0)
      .toUint8());
  }

  private static samsungTag(id: number, name: string): Uint8Array {
    return new ByteWriter().writeShortLe(0).writeShortLe(id).writeIntLe(name.length)
      .writeAscii(name).toUint8();
  }

  private static samsungFooter(videoLength: number, prefixSize: number): Uint8Array {
    const version = MotionPhotoContainer.samsungTag(0x0a31, 'MotionPhoto_Version');
    version.set(MotionPhotoContainer.asciiBytes('mpv3'), version.length - 4);
    const dataLength = prefixSize + videoLength;
    const w = new ByteWriter();
    w.writeAscii('SEFH').writeIntLe(107).writeIntLe(2);
    w.writeShortLe(0).writeShortLe(0x0a30).writeIntLe(dataLength + version.length).writeIntLe(dataLength);
    w.writeShortLe(0).writeShortLe(0x0a31).writeIntLe(version.length).writeIntLe(version.length);
    w.writeIntLe(36).writeAscii('SEFT');
    const index = w.toUint8();
    const out = new Uint8Array(version.length + index.length);
    out.set(version, 0);
    out.set(index, version.length);
    return out;
  }

  private static huaweiTail(videoLength: number, videoFrameCount: number): Uint8Array {
    if (videoLength <= 0 || videoFrameCount <= 0) {
      throw new Error('Invalid huawei tail parameters');
    }
    const out = new Uint8Array(60);
    out.fill(0x20);
    MotionPhotoContainer.field(out, 0, 'v6_f0', 6);
    MotionPhotoContainer.field(out, 20, `0:${videoFrameCount}`, 8);
    MotionPhotoContainer.field(out, 40, `LIVE_${videoLength + 20}`, 15);
    return out;
  }

  private static field(target: Uint8Array, offset: number, value: string, maxLength: number): void {
    if (value.length > maxLength) {
      throw new Error('Huawei tail field overflow');
    }
    for (let i = 0; i < value.length; i++) {
      target[offset + i] = value.charCodeAt(i) & 0xff;
    }
  }

  static vivoImageTail(id: string): Uint8Array {
    return MotionPhotoContainer.vivoTail(id,
      'vivo{"com.vivo.gallery.livephoto.source":4,"com.vivo.gallery.livePhoto.rotationOffset":0,' +
      '"com.vivo.gallery.livePhoto.rotationCheck":3,"com.android.camera.livephoto":"' + id + '","version":2200}');
  }

  static vivoVideoBox(id: string): Uint8Array {
    const tail = MotionPhotoContainer.vivoTail(id,
      'vivo{"com.android.camera.livephoto":"' + id + '","version":2016,' +
      '"com.vivo.gallery.livePhoto.newCoverTime":0}');
    // The observed user type occupies the complete 16-byte UUID user-type field.
    return new ByteWriter().writeInt(24 + tail.length).writeAscii('uuidvivoMediaExtInfo')
      .writeBytes(tail).toUint8();
  }

  private static vivoTail(id: string, json: string): Uint8Array {
    if (!/^[0-9a-f]{28}$/.test(id)) {
      throw new Error('Invalid vivo pair id');
    }
    const data = MotionPhotoContainer.utf8Bytes(json);
    return new ByteWriter().writeBytes(data).writeInt(data.length - 4).writeAscii('cameralbum!')
      .writeInt(id.length + 19).writeAscii(id).writeInt(-1)
      .writeByte(0x1b).writeByte(0x2a).writeByte(0x39).writeByte(0x48).writeByte(0x57)
      .writeByte(0x66).writeByte(0x75).writeByte(0x84).writeByte(0x93).writeByte(0xa2).writeByte(0xb3)
      .toUint8();
  }

  private static asciiBytes(text: string): Uint8Array {
    const out = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) {
      out[i] = text.charCodeAt(i) & 0xff;
    }
    return out;
  }

  private static utf8Bytes(text: string): Uint8Array {
    const out: number[] = [];
    for (let i = 0; i < text.length; i++) {
      let code = text.charCodeAt(i);
      if (code < 0x80) {
        out.push(code);
      } else if (code < 0x800) {
        out.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
      } else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
        const low = text.charCodeAt(i + 1);
        code = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
        i++;
        out.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f),
          0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
      } else {
        out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
      }
    }
    return new Uint8Array(out);
  }
}
