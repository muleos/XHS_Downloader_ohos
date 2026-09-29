/** Byte writer (big-endian DataOutputStream parity). */
export class ByteWriter {
  private buf: number[] = [];

  writeByte(v: number): ByteWriter {
    this.buf.push(v & 0xff);
    return this;
  }

  writeBytes(bytes: Uint8Array): ByteWriter {
    for (let i = 0; i < bytes.length; i++) {
      this.buf.push(bytes[i] & 0xff);
    }
    return this;
  }

  writeAscii(text: string): ByteWriter {
    for (let i = 0; i < text.length; i++) {
      this.buf.push(text.charCodeAt(i) & 0xff);
    }
    return this;
  }

  writeShort(v: number): ByteWriter {
    this.buf.push((v >>> 8) & 0xff, v & 0xff);
    return this;
  }

  writeShortLe(v: number): ByteWriter {
    this.buf.push(v & 0xff, (v >>> 8) & 0xff);
    return this;
  }

  writeInt(v: number): ByteWriter {
    this.buf.push((v >>> 24) & 0xff, (v >>> 16) & 0xff, (v >>> 8) & 0xff, v & 0xff);
    return this;
  }

  writeIntLe(v: number): ByteWriter {
    this.buf.push(v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff);
    return this;
  }

  toUint8(): Uint8Array {
    return new Uint8Array(this.buf);
  }
}

/** Reads bytes at arbitrary offsets (RandomAccessFile parity). */
export class ByteReader {
  readonly bytes: Uint8Array;

  constructor(bytes: Uint8Array) {
    this.bytes = bytes;
  }

  get length(): number {
    return this.bytes.length;
  }

  u8(at: number): number {
    return this.bytes[at] & 0xff;
  }

  u16(at: number): number {
    return ((this.bytes[at] & 0xff) << 8) | (this.bytes[at + 1] & 0xff);
  }

  u16Le(at: number): number {
    return ((this.bytes[at + 1] & 0xff) << 8) | (this.bytes[at] & 0xff);
  }

  u32(at: number): number {
    return ((this.bytes[at] & 0xff) * 0x1000000) + ((this.bytes[at + 1] & 0xff) << 16) +
      ((this.bytes[at + 2] & 0xff) << 8) + (this.bytes[at + 3] & 0xff);
  }

  u32Le(at: number): number {
    return ((this.bytes[at + 3] & 0xff) * 0x1000000) + ((this.bytes[at + 2] & 0xff) << 16) +
      ((this.bytes[at + 1] & 0xff) << 8) + (this.bytes[at] & 0xff);
  }

  /** Unsigned 32-bit as safe number. */
  u32U(at: number): number {
    return this.u32(at) >>> 0;
  }

  i32(at: number): number {
    return this.u32(at) | 0;
  }

  ascii(at: number, size: number): string {
    let s = '';
    for (let i = at; i < at + size && i < this.bytes.length; i++) {
      s += String.fromCharCode(this.bytes[i] & 0xff);
    }
    return s;
  }

  slice(start: number, end: number): Uint8Array {
    return this.bytes.slice(start, end);
  }
}
