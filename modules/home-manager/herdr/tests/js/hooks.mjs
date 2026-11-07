// Loaded with `node --import`: resolves the modules only herdr-app provides
// ("herdr", "gpui-kit", "gpui-base") to the stubs beside this file, so mod
// code that imports them loads under plain Node.

import { registerHooks } from "node:module";

const STUBS = {
  herdr: new URL("./stubs/herdr.mjs", import.meta.url).href,
  "gpui-kit": new URL("./stubs/gpui.mjs", import.meta.url).href,
  "gpui-base": new URL("./stubs/gpui.mjs", import.meta.url).href,
};

registerHooks({
  resolve(specifier, context, next) {
    return specifier in STUBS ? { url: STUBS[specifier], shortCircuit: true } : next(specifier, context);
  },
});
