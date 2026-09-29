/** Pure-TS SHA-256 (fingerprint parity with ResumableTransfer.kt). */
export class Sha256 {
  private static readonly K: number[] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ];

  static digestHex(input: string): string {
    // UTF-8 encode
    const bytes: number[] = [];
    for (let i = 0; i < input.length; i++) {
      let c = input.charCodeAt(i);
      if (c < 0x80) {
        bytes.push(c);
      } else if (c < 0x800) {
        bytes.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
      } else if (c >= 0xd800 && c < 0xdc00 && i + 1 < input.length) {
        const lo = input.charCodeAt(++i);
        c = 0x10000 + ((c - 0xd800) << 10) + (lo - 0xdc00);
        bytes.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
      } else {
        bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
      }
    }
    const bitLen = bytes.length * 8;
    bytes.push(0x80);
    while (bytes.length % 64 !== 56) {
      bytes.push(0);
    }
    for (let i = 7; i >= 0; i--) {
      bytes.push((i >= 4 ? 0 : (bitLen / Math.pow(2, i * 8))) & 0xff);
    }
    let h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    let h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;
    const w: number[] = new Array<number>(64);
    for (let off = 0; off < bytes.length; off += 64) {
      for (let t = 0; t < 16; t++) {
        w[t] = (bytes[off + t * 4] << 24) | (bytes[off + t * 4 + 1] << 16) |
          (bytes[off + t * 4 + 2] << 8) | bytes[off + t * 4 + 3];
      }
      for (let t = 16; t < 64; t++) {
        const s0 = Sha256.rotr(w[t - 15], 7) ^ Sha256.rotr(w[t - 15], 18) ^ (w[t - 15] >>> 3);
        const s1 = Sha256.rotr(w[t - 2], 17) ^ Sha256.rotr(w[t - 2], 19) ^ (w[t - 2] >>> 10);
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) | 0;
      }
      let a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (let t = 0; t < 64; t++) {
        const S1 = Sha256.rotr(e, 6) ^ Sha256.rotr(e, 11) ^ Sha256.rotr(e, 25);
        const ch = (e & f) ^ (~e & g);
        const temp1 = (h + S1 + ch + Sha256.K[t] + w[t]) | 0;
        const S0 = Sha256.rotr(a, 2) ^ Sha256.rotr(a, 13) ^ Sha256.rotr(a, 22);
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const temp2 = (S0 + maj) | 0;
        h = g; g = f; f = e; e = (d + temp1) | 0;
        d = c; c = b; b = a; a = (temp1 + temp2) | 0;
      }
      h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0;
      h4 = (h4 + e) | 0; h5 = (h5 + f) | 0; h6 = (h6 + g) | 0; h7 = (h7 + h) | 0;
    }
    let out = '';
    const hs = [h0, h1, h2, h3, h4, h5, h6, h7];
    for (const value of hs) {
      out += Sha256.hex8(value);
    }
    return out;
  }

  private static rotr(x: number, n: number): number {
    return (x >>> n) | (x << (32 - n));
  }

  private static hex8(v: number): string {
    let s = '';
    for (let i = 7; i >= 0; i--) {
      const nibble = (v >>> (i * 4)) & 0xf;
      s += nibble < 10 ? String(nibble) : String.fromCharCode(87 + nibble);
    }
    return s;
  }
}
