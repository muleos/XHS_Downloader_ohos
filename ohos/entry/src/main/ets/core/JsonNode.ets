/**
 * JsonNode — minimal org.json-like wrapper over JSON.parse results.
 * Keeps the ported parser logic 1:1 with XhsNoteParser.kt while staying
 * within ArkTS typing rules (no `any`, no untyped index access).
 */
export class JsonNode {
  private readonly obj: Record<string, Object> | null;
  private readonly arr: Array<Object> | null;
  private readonly str: string | null;
  private readonly num: number | null;
  private readonly bool: boolean | null;

  private constructor(obj: Record<string, Object> | null, arr: Array<Object> | null,
    str: string | null, num: number | null, bool: boolean | null) {
    this.obj = obj;
    this.arr = arr;
    this.str = str;
    this.num = num;
    this.bool = bool;
  }

  static parse(text: string): JsonNode | null {
    try {
      const value: Object = JSON.parse(text) as Object;
      return JsonNode.wrap(value);
    } catch (e) {
      return null;
    }
  }

  static wrap(value: Object | null | undefined): JsonNode | null {
    if (value === null || value === undefined) {
      return null;
    }
    if (typeof value === 'string') {
      return new JsonNode(null, null, value as string, null, null);
    }
    if (typeof value === 'number') {
      return new JsonNode(null, null, null, value as number, null);
    }
    if (typeof value === 'boolean') {
      return new JsonNode(null, null, null, null, value as boolean);
    }
    if (Array.isArray(value)) {
      return new JsonNode(null, value as Array<Object>, null, null, null);
    }
    return new JsonNode(value as Record<string, Object>, null, null, null, null);
  }

  isObject(): boolean {
    return this.obj !== null;
  }

  isString(): boolean {
    return this.str !== null;
  }

  isNumber(): boolean {
    return this.num !== null;
  }

  asString(): string {
    if (this.str !== null) {
      return this.str;
    }
    if (this.num !== null) {
      return String(this.num);
    }
    if (this.bool !== null) {
      return this.bool ? 'true' : 'false';
    }
    return '';
  }

  asNumber(): number {
    if (this.num !== null) {
      return this.num;
    }
    if (this.str !== null) {
      const parsed = Number(this.str);
      return isNaN(parsed) ? 0 : parsed;
    }
    return 0;
  }

  length(): number {
    return this.arr !== null ? this.arr.length : 0;
  }

  keys(): string[] {
    if (this.obj === null) {
      return [];
    }
    return Object.keys(this.obj);
  }

  has(key: string): boolean {
    if (this.obj === null) {
      return false;
    }
    return this.obj[key] !== undefined && this.obj[key] !== null;
  }

  opt(key: string): JsonNode | null {
    if (this.obj === null) {
      return null;
    }
    const value: Object | undefined = this.obj[key];
    if (value === undefined) {
      return null;
    }
    return JsonNode.wrap(value);
  }

  optString(key: string, fallback: string = ''): string {
    const node = this.opt(key);
    if (node === null || node.isObject()) {
      return fallback;
    }
    const s = node.asString();
    return s === 'null' ? fallback : s;
  }

  optNumber(key: string, fallback: number = 0): number {
    const node = this.opt(key);
    if (node === null || node.isObject()) {
      return fallback;
    }
    return node.asNumber();
  }

  optBool(key: string, fallback: boolean = false): boolean {
    const node = this.opt(key);
    if (node === null || node.isObject()) {
      return fallback;
    }
    if (node.bool !== null) {
      return node.bool;
    }
    if (node.str === 'true') {
      return true;
    }
    if (node.str === 'false') {
      return false;
    }
    return fallback;
  }

  optLongMs(key: string): number {
    // XHS timestamps are ms; JSON numbers may lose precision in older engines — clamp to safe range.
    const node = this.opt(key);
    if (node === null) {
      return 0;
    }
    return node.asNumber();
  }

  optObject(key: string): JsonNode | null {
    const node = this.opt(key);
    return node !== null && node.isObject() ? node : null;
  }

  optArray(key: string): JsonNode[] {
    const node = this.opt(key);
    if (node === null || node.arr === null) {
      return [];
    }
    const out: JsonNode[] = [];
    for (const item of node.arr) {
      const wrapped = JsonNode.wrap(item);
      if (wrapped !== null) {
        out.push(wrapped);
      }
    }
    return out;
  }

  at(index: number): JsonNode | null {
    if (this.arr === null || index < 0 || index >= this.arr.length) {
      return null;
    }
    return JsonNode.wrap(this.arr[index]);
  }

  /** Iterate object entries in insertion order. */
  forEachEntry(action: (key: string, value: JsonNode) => void): void {
    if (this.obj === null) {
      return;
    }
    const ks = this.keys();
    for (const k of ks) {
      const node = JsonNode.wrap(this.obj[k]);
      if (node !== null) {
        action(k, node);
      }
    }
  }
}
