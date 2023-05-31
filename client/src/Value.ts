
export class Bool {
  private _v: string

  constructor(x: boolean) {
    this._v = x ? '0x1' : '0x0';
  }

  get(): string {
    return this._v;
  }
}

export class Address {
  private _v: string

  constructor(x: string) {
    this._v = x;
  }

  get(): string {
    return this._v;
  }
}

export class Uint256 {
  private _v: string

  constructor(x: string | number) {
    if (typeof(x) === 'string') {
      this._v = x;
    } else {
      // TODO: Check number size?
      this._v = `0x${x.toString(16)}`;  
    }
  }

  get(): string {
    return this._v;
  }
}

export class Bytes {
  private _v: string

  constructor(x: string) {
    this._v = x;
  }

  get(): string {
    return this._v;
  }
}

export class Variable<T> {
  private _v: string

  constructor(x: string) {
    this._v = x;
  }

  get(): string {
    return this._v;
  }
}

export type Value<T> = T | Variable<T>;
export type ValueType = Bytes | Uint256 | Address;
