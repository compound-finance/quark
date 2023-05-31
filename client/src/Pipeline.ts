import type { Action } from './Action';

/** A pipeline represents a set of built-ins that are meant to be run
 *  serially. The built-ins themselves can have inputs and outputs that
 *  reference other built-ins. This is tracked in a dependency graph.
 */

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
