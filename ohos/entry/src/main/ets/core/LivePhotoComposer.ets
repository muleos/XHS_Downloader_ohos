/**
 * Ported from LivePhotoCreator.kt — device-specific live photo assembly without
 * changing the source video or its audio tracks. JPEG conversion uses the ohos
 * image kit; container assembly is byte-exact MotionPhotoContainer; track
 * validation uses BmffProbe (replaces MediaExtractor).
 */
import { image } from '@kit.ImageKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { LivePhotoFormat } from './models';
import { MotionPhotoContainer, ContainerLayout } from './MotionPhotoContainer';
import { BmffProbe } from './BmffProbe';
import { ExifWriter } from './ExifWriter';
import { ByteReader } from './ByteReader';

/** Port of LivePhotoFormat.resolve(manufacturer, brand) + vendor comment policy. */
export class LivePhotoFormatResolver {
  static resolve(format: LivePhotoFormat, manufacturer: string, brand: string): LivePhotoFormat {
    if (format !== LivePhotoFormat.AUTO) {
      return format;
    }
    const names = [manufacturer.toLowerCase(), brand.toLowerCase()];
    const inSet = (set: string[]): boolean => {
      for (const name of names) {
        for (const candidate of set) {
          if (name === candidate) {
            return true;
          }
        }
      }
      return false;
    };
    if (inSet(['oppo', 'oneplus', 'realme'])) {
      return LivePhotoFormat.OPLUS;
    }
    if (inSet(['xiaomi', 'redmi'])) {
      return LivePhotoFormat.XIAOMI;
    }
    if (inSet(['samsung'])) {
      return LivePhotoFormat.SAMSUNG;
    }
    if (inSet(['vivo', 'iqoo'])) {
      return LivePhotoFormat.VIVO;
    }
    if (inSet(['huawei', 'honor'])) {
      return LivePhotoFormat.HUAWEI;
    }
    return LivePhotoFormat.STANDARD;
  }

  /** Only OPLUS and VIVO carry a UserComment marker (parity with addVendorExif). */
  static vendorComment(format: LivePhotoFormat): string {
    if (format === LivePhotoFormat.OPLUS) {
      return 'Oplus_8388608';
    }
    if (format === LivePhotoFormat.VIVO) {
      return LivePhotoFormatResolver.vivoUserComment(new Date());
    }
    return '';
  }

  static vivoUserComment(now: Date): string {
    const p = (n: number): string => (n < 10 ? '0' + String(n) : String(n));
    const date = `${now.getFullYear()}:${p(now.getMonth() + 1)}:${p(now.getDate())} ` +
      `${p(now.getHours())}:${p(now.getMinutes())}:${p(now.getSeconds())}`;
    return 'filter: 2237; fileterIntensity: 0.000000; fileterType: none; captureMode: 0; beauty: 0; ' +
      'beautyLevel: 0; beautySkin: 0; beautyWhite: 0; beautySlim: 0; filterName: none; stage: 0; ' +
      `dateTime: ${date}; frontCamera: 0`;
  }
}

export class ComposeResult {
  warnings: string[] = [];
  outputBytes: Uint8Array | null = null;
  secondOutputBytes: Uint8Array | null = null;
}

export class LivePhotoComposer {
  static resolveFormat(format: LivePhotoFormat): LivePhotoFormat {
    return LivePhotoFormatResolver.resolve(format, deviceInfo.manufacture, deviceInfo.brand);
  }

  /** Full MERGED pipeline: convert → (vendor exif) → assemble → verify. */
  static async compose(imageBytes: Uint8Array, videoBytes: Uint8Array, format: LivePhotoFormat): Promise<ComposeResult> {
    const result = new ComposeResult();
    const resolved = LivePhotoComposer.resolveFormat(format);
    if (resolved === LivePhotoFormat.AUTO || resolved === LivePhotoFormat.VIVO_LEGACY) {
      throw new Error('Format requires resolution before composition');
    }
    const videoMime = MotionPhotoContainer.videoMime(videoBytes);
    const tracks = BmffProbe.inspect(videoBytes, 0, videoBytes.length);
    if (tracks.mimeTypes.length === 0) {
      throw new Error('Video has no readable track');
    }
    const frameCount = BmffProbe.frameCount(videoBytes, 0, videoBytes.length);
    const jpeg = await LivePhotoComposer.convertToJpeg(imageBytes, result.warnings);
    let tagged = jpeg;
    const comment = LivePhotoFormatResolver.vendorComment(resolved);
    if (comment.length > 0) {
      tagged = ExifWriter.insert(jpeg, 1, comment);
    }
    MotionPhotoContainer.write(tagged, videoBytes, resolved, videoMime, frameCount);
    result.outputBytes = MotionPhotoContainer.lastOutput;
    const layout: ContainerLayout | null = MotionPhotoContainer.lastLayout;
    if (layout !== null) {
      const verify = BmffProbe.inspect(result.outputBytes, layout.videoOffset, layout.videoLength);
      if (!verify.equals(tracks)) {
        result.warnings.push('TRACK_MISMATCH');
      }
    } else {
      result.warnings.push('LAYOUT_MISSING');
    }
    return result;
  }

  /** VIVO_LEGACY pair: image tail + fixed-up video with uuid box; either half is reusable. */
  static async composeVivoPair(imageBytes: Uint8Array, videoBytes: Uint8Array, pairId: string): Promise<ComposeResult> {
    const result = new ComposeResult();
    if (MotionPhotoContainer.videoMime(videoBytes) !== 'video/mp4') {
      throw new Error('VIVO pair requires MP4');
    }
    const image = await LivePhotoComposer.convertToJpeg(imageBytes, result.warnings);
    const tail = MotionPhotoContainer.vivoImageTail(pairId);
    const merged = new Uint8Array(image.length + tail.length);
    merged.set(image, 0);
    merged.set(tail, image.length);
    result.outputBytes = merged;

    const video = LivePhotoComposer.copyVideoWithVivoBox(videoBytes, pairId, result.warnings);
    result.secondOutputBytes = video;
    const verify = BmffProbe.inspect(video, 0, video.length);
    const tracks = BmffProbe.inspect(videoBytes, 0, videoBytes.length);
    if (!verify.equals(tracks)) {
      result.warnings.push('TRACK_MISMATCH');
    }
    return result;
  }

  /** Terminate a size-zero final box and append uuid vivoMediaExtInfo (parity). */
  static copyVideoWithVivoBox(videoBytes: Uint8Array, pairId: string, warnings: string[]): Uint8Array {
    const fixed = new Uint8Array(videoBytes);
    const reader = new ByteReader(fixed);
    let fixed0 = false;
    try {
      fixed0 = BmffProbe.fixZeroTerminator(reader);
    } catch (e) {
      // Size-zero terminator larger than u32: keep original bytes.
    }
    if (!fixed0) {
      warnings.push('VIVO_BOX_UNFIXED');
    }
    const box = MotionPhotoContainer.vivoVideoBox(pairId);
    const out = new Uint8Array(fixed.length + box.length);
    out.set(fixed, 0);
    out.set(box, fixed.length);
    return out;
  }

  /** Any supported still format → JPEG (q95) with EXIF orientation normalized. */
  static async convertToJpeg(bytes: Uint8Array, warnings: string[]): Promise<Uint8Array> {
    const head = new ByteReader(bytes);
    const isJpeg = head.u16(0) === 0xffd8;
    let orientation = 1;
    try {
      const probe = image.createImageSource(bytes.slice(0, 2048).buffer as ArrayBuffer);
      const raw = await probe.getImageProperty(image.PropertyKey.ORIENTATION);
      orientation = LivePhotoComposer.orientationValue(raw);
      probe.release();
    } catch (e) {
      orientation = 1;
    }
    const source = image.createImageSource(bytes.buffer as ArrayBuffer);
    try {
      const pixelMap: image.PixelMap = await source.createPixelMap();
      const degrees = LivePhotoComposer.rotationDegrees(orientation);
      if (degrees === 90) {
        pixelMap.rotate(90);
      } else if (degrees === 180) {
        pixelMap.rotate(180);
      } else if (degrees === 270) {
        pixelMap.rotate(270);
      }
      if (orientation === 2 || orientation === 5 || orientation === 7) {
        pixelMap.flip(false, true);
      } else if (orientation === 4) {
        pixelMap.flip(true, false);
      }
      const packer = image.createImagePacker();
      const opts: image.PackingOption = { format: 'image/jpeg', quality: 95 };
      const packed = await packer.packToData(pixelMap, opts);
      if (isJpeg) {
        warnings.push('JPEG_REENCODED');
      } else {
        warnings.push('JPEG_CONVERTED');
      }
      return new Uint8Array(packed);
    } catch (e) {
      if (isJpeg) {
        warnings.push('JPEG_KEEP_ORIGINAL');
        return bytes;
      }
      throw new Error('Image conversion failed');
    } finally {
      source.release();
    }
  }

  private static orientationValue(raw: string): number {
    switch (raw) {
      case 'top-left': return 1;
      case 'top-right': return 2;
      case 'bottom-right': return 3;
      case 'bottom-left': return 4;
      case 'left-top': return 5;
      case 'right-top': return 6;
      case 'right-bottom': return 7;
      case 'left-bottom': return 8;
      default: return 1;
    }
  }

  private static rotationDegrees(orientation: number): number {
    if (orientation === 5 || orientation === 6) {
      return 90;
    }
    if (orientation === 3 || orientation === 4) {
      return 180;
    }
    if (orientation === 7 || orientation === 8) {
      return 270;
    }
    return 0;
  }
}
