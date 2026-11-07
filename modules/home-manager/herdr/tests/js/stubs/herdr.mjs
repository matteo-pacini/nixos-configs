// Stand-in for herdr-app's "herdr" module. Every call goes to a handler a
// test installs with `mock({ exec: (cmd, args, opts) => ... })`; one that
// isn't installed throws, so a test can't silently depend on it. `calls`
// records each call as [name, ...args].

export const calls = [];
let handlers = {};

/** Replaces the handlers and clears `calls`. */
export function mock(next) {
  handlers = next;
  calls.length = 0;
}

const stub = (name) => (...args) => {
  calls.push([name, ...args]);
  if (!handlers[name]) throw new Error(`herdr stub: ${name}() has no handler in this test`);
  return handlers[name](...args);
};

export const exec = stub("exec");
export const hc = stub("hc");
export const notify = stub("notify");
export const readTextFile = stub("readTextFile");
export const focused = stub("focused");
export const layout = stub("layout");
export const panes = stub("panes");
export const spaces = stub("spaces");
export const window = stub("window");
