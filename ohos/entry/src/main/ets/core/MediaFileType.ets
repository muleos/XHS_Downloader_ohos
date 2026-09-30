/** Ported from data/network/MediaFileType.kt — signature sniffing for extensions. */
export class MediaFileType {
  extension: string;
  mimeType: string;

  constructor(extension: string, mimeType: string) {
    this.extension = extension;
    this.mimeType = mimeType;
  }

  static detect(head: ArrayBuffer): MediaFileType | null {
    if (head.byteLength < 12) {
      return null;
    }
    const bytes = new Uint8Array(head, 0, Math.min(32, head.byteLength));
    const starts = (signature: number[]): boolean => {
      if (bytes.length < signature.length) {
        return false;
      }
      for (let i = 0; i < signature.length; i++) {
        if ((bytes[i] & 0xff) !== signature[i]) {
          return false;
        }
      }
      return true;
    };
    const textAt = (offset: number, size: number): string => {
      let s = '';
      for (let i = offset; i < Math.min(offset + size, bytes.length); i++) {
        s += String.fromCharCode(bytes[i] & 0xff);
      }
      return s;
    };
    if (starts([0xff, 0xd8, 0xff])) {
      return new MediaFileType('jpg', 'image/jpeg');
    }
    if (starts([0x89, 0x50, 0x4e, 0x47])) {
      return new MediaFileType('png', 'image/png');
    }
    if (textAt(0, 4) === 'GIF8') {
      return new MediaFileType('gif', 'image/gif');
    }
    if (textAt(0, 4) === 'RIFF' && textAt(8, 4) === 'WEBP') {
      return new MediaFileType('webp', 'image/webp');
    }
    // MP4 开头 4 字节是首个 box 的大小（如 00 00 00 18），不能要求全零；
    // 旧写法 starts([0,0,0,0]) 对所有真实 MP4 恒为 false → 视频全部被误判
    // 为 unknown signature → 整个视频资源下载失败（v1.15.0 修复）。
    if (textAt(4, 4) === 'ftyp') {
      const brand = textAt(8, 4).toLowerCase();
      if (brand.startsWith('qt')) {
        return new MediaFileType('mov', 'video/quicktime');
      }
      if (brand.startsWith('heic') || brand.startsWith('heix') || brand.startsWith('heim')) {
        return new MediaFileType('heic', 'image/heic');
      }
      if (brand.startsWith('avif') || brand.startsWith('avis')) {
        return new MediaFileType('avif', 'image/avif');
      }
      return new MediaFileType('mp4', 'video/mp4');
    }
    if (textAt(0, 2) === 'BM') {
      return new MediaFileType('bmp', 'image/bmp');
    }
    return null;
  }
}
