import { Yul, yul } from './Yul';
import { Value, ValueType, Variable } from './Value';

/** A builtin action represents an atomic action that can be run itself or as
 *  part of a pipeline. These should be 1:1 with Yul functions. They have some
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

export interface Action<T> {
  preamble: Yul[],
  statements: Yul[],
  description: string,
  _: T | undefined,
}

// Just use a global var for unique ids
let varIndex = 0;

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

export function __resetVarIndex() {
  varIndex = 0;
}
