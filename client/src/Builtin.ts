import { Output, compile } from 'solc';

export class Builtin {
  /** A builtin represents an atomic action that can be run itself or as part
   *  of a pipeline. These should be 1:1 with Yul functions. They have some
   *  fancy features to display helpful information to users.
   *
   *  Note: Built-ins are not inherently safe! You must trust the built-in
   *        is coming from a reputable source, and even so, it may contain
   *        bugs!
   * 
   *  Note: Built-ins will emit Yul code (in the form of lisp-style execution),
   *        and cannot depend on any helper functions except as specified
   *        in its dependency list.
   * 
   *  Note: The only exception to the above is that built-ins may rely on
   *        a standard `allocate` function and are expected to abide by it
   *        as the only form of accessing memory.
   */


  
}

interface Executor {}

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
type ValueType = Bytes | Uint256 | Address;

type Yul = string;

function indentLen(s: string): number {
  return s.length - s.replace(/^\s*/, '').length
}

export function yul(template: TemplateStringsArray, ...params: (Yul | Value<ValueType>)[]): Yul {
  let res = template.reduce((acc, t, i) => {
    let p = params[i];
    return acc + t + ( p === undefined ? '' : ( typeof(p) === 'string' ? p : p.get() ) )
  }, '');

  let minIndent = Math.min(...res.split('\n').filter((s) => s.match(/\w/)).map(indentLen))
  let regexpInner = [...new Array(minIndent)].map((_) => '\\s').join('');
  let regex = new RegExp(`^${regexpInner}`, 'mg')
  return res.trim().replace(regex, '');
}

export function callSig(abi: string): Value<Bytes> {
  return new Bytes('0x00112233');
}

export interface Action<T> {
  preamble: Yul[],
  statements: Yul[],
  description: string,
  _: T | undefined,
}

// Just use a global var for unique ids
let varIndex = 0;

let cometAddress = new Address("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");

export function cUSDCv3Supply(asset: Value<Address>, amount: Value<Uint256>): Action<Bool> {
  return {
    preamble: [
      yul`
        function cUSDCv3Supply(asset, amount) -> success {
          let data := allocate(0x44)
          let sig := ${callSig('supply(address,uint256)')}
          mstore(data, sig)
          mstore(add(data, 0x04), asset)
          mstore(add(data, 0x24), amount)
          success := call(gas(), ${cometAddress}, 0, data, 0x44, 0, 0)
        }
      `],
    statements: [
      `cUSDCv3Supply(${asset.get()}, ${amount.get()})`
    ],
    description: `Supply to Comet [cUSDCv3][Mainnet]`, // TODO: This is weird and wrong
    _: undefined,
  }
}

export function pipe<T, U>(action0: Action<T>, f: (r: Value<T>) => Action<U>): Action<U> {
  let variable = new Variable<T>(`__v__${varIndex++}`);
  let action1 = f(variable); // Variable acts as type (todo: avoid as?)

  let statements = [...action0.statements];
  let lastStatement = statements.pop();

  if (!lastStatement) {
    throw new Error(`Invalid action: ${action0}: missing core statement`);
  }

  return {
    preamble: [...action0.preamble, ...action1.preamble],
    statements: [
      ...statements,
      yul`let ${variable.get()} := ${lastStatement}`,
      ...action1.statements
    ],
    description: `${action0.description} |> ${action1.description}`,
    _: undefined
  }
}

export function pop<T extends ValueType>(action: Action<T>): Action<undefined> {
  let statements = [...action.statements];
  let lastStatement = statements.pop();

  if (!lastStatement) {
    throw new Error(`Invalid action: ${action}: missing core statement`);
  }

  return {
    preamble: action.preamble,
    statements: [
      ...statements,
      yul`pop(${lastStatement})`
    ],
    description: action.description,
    _: undefined
  }
}

export function pipeline(actions: Action<undefined>[]): Action<undefined> {
  let vars = [];
  return actions.reduce<Action<undefined>>(({preamble, statements, description}, el: Action<undefined>) => {
    return {
      preamble: [...new Set([...preamble, ...el.preamble])],
      statements: [...statements, ...el.statements],
      description: `${description}\n  * ${el.description}`,
      _: undefined
    };
  }, { preamble: [], statements: [], description: 'Pipeline:', _: undefined });
}

interface Command {
  yul: string,
  description: string,
  bytecode: string
}

function indent(n: number): (s: string) => string {
  let indention = [...new Array(n)].map((_) => ' ').join('');

  return function(s: string): string {
    return s.split('\n').map((x) => indention + x).join('\n');
  }
}

export function prepare(action: Action<undefined>): Command {
  let yul = `
object "QuarkCommand" {
  code {
    verbatim_0i_0o(hex"303030505050")

${action.preamble.map(indent(4)).join('\n\n')}

${action.statements.map(indent(4)).join('\n\n')}
  }
}`;

  console.log("Yul");
  console.log(yul);

  let input = {
    language: 'Yul',
    sources: {
      'q.yul': {
        content: yul
      }
    },
    settings: {
      optimizer: {
        enabled: true,
        runs: 1
      },
      evmVersion: "paris",
      outputSelection: {
        'q.yul': {
          '*': ['evm.bytecode.object']
        }
      }
    }
  };

  let yulCompilationRes = JSON.parse(compile(JSON.stringify(input))) as Output;
  console.log(yulCompilationRes);
  let bytecode = Object.values(yulCompilationRes.contracts['q.yul'])[0].evm.bytecode.object as string;

  if (!bytecode.startsWith('303030505050')) {
    throw new Error(`Invalid bytecode produced, does not start with magic incantation 0x303030505050, got: ${bytecode}`);
  }

  return {
    yul,
    description: action.description,
    bytecode: `0x` + bytecode
  };
}

export const Comet = {
  supply: cUSDCv3Supply
};
