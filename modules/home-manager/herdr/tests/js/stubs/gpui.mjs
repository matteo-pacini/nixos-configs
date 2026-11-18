// Stand-in for herdr-app's "gpui-kit" and "gpui-base": builds a plain tree a
// test can search and click, and paints nothing. Every style call is a no-op
// that returns the element, except:
//   id(x)            -> el.key
//   child / children -> el.kids
//   when(cond, fn)   -> fn(el) when cond is truthy
//   on_*(…, fn)      -> el.on[name] = fn (its last argument), e.g. el.on.on_click

const RECORDED = {
  id(el, id) {
    el.key = id;
  },
  child(el, c) {
    el.kids.push(c);
  },
  children(el, cs) {
    el.kids.push(...cs);
  },
};

function element(kind, arg) {
  const el = { kind, arg, key: null, kids: [], on: {} };
  const proxy = new Proxy(el, {
    get(target, name) {
      if (name in target) return target[name];
      if (typeof name !== "string") return undefined;
      if (name === "when") return (cond, fn) => (cond ? fn(proxy) : proxy);
      return (...args) => {
        if (RECORDED[name]) RECORDED[name](target, ...args);
        else if (name.startsWith("on_")) target.on[name] = args.at(-1);
        return proxy;
      };
    },
  });
  return proxy;
}

export class View {}
export const div = () => element("div");
export const v_flex = () => element("v_flex");
export const h_flex = () => element("h_flex");
export const svg = (path) => element("svg", path);
export const image = (path) => element("image", path);

/** The element with `id` under `root` (depth first), or null. */
export function find(root, id) {
  if (!root || typeof root !== "object") return null;
  if (root.key === id) return root;
  for (const c of root.kids ?? []) {
    const found = find(c, id);
    if (found) return found;
  }
  return null;
}
