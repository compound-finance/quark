import type { Value, ValueType } from './Value';

export type Yul = string;

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
  return res.replace(regex, '').trim();
}
