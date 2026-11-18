// Loaded with `node --import`: resolves the modules only herdr-app provides
// ("herdr", "gpui-kit", "gpui-base") and the per-machine lib/hosts.js that
// workbench.nix generates to the stubs beside this file, so mod code that
// imports them loads under plain Node.

import { registerHooks } from "node:module";

const STUBS = {
  herdr: new URL("./stubs/herdr.mjs", import.meta.url).href,
  "gpui-kit": new URL("./stubs/gpui.mjs", import.meta.url).href,
  "gpui-base": new URL("./stubs/gpui.mjs", import.meta.url).href,
};
const HOSTS = new URL("./stubs/hosts.mjs", import.meta.url).href;

registerHooks({
  resolve(specifier, context, next) {
    if (specifier in STUBS) return { url: STUBS[specifier], shortCircuit: true };
    if (specifier.endsWith("/lib/hosts.js")) return { url: HOSTS, shortCircuit: true };
    return next(specifier, context);
  },
});
