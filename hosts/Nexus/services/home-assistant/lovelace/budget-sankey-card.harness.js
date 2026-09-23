// Loads budget-sankey-card.js for the tests. The card is a browser script, so
// it runs in a vm context with just enough DOM stubbed for the element to
// construct and render, and a clock the tests set. The rendered markup is left
// as a string on el.shadowRoot.innerHTML for the tests to inspect.

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const ctx = vm.createContext({});
vm.runInContext(
  `
  var __now = "2026-09-24T12:00:00";
  const __RealDate = Date;
  Date = class extends __RealDate {
    constructor(...a) { super(...(a.length ? a : [__now])); }
    static now() { return new __RealDate(__now).getTime(); }
  };
  class HTMLElement {
    attachShadow() {
      return (this.shadowRoot = { innerHTML: "", querySelector: () => null, querySelectorAll: () => [] });
    }
  }
  var customElements = { define(name, cls) { this.name = name; this.cls = cls; } };
  var window = {};
  var ResizeObserver = class { observe() {} disconnect() {} };
  `,
  ctx
);
vm.runInContext(fs.readFileSync(path.join(__dirname, "budget-sankey-card.js"), "utf8"), ctx);

module.exports = {
  ctx,
  // The card's top-level declarations, which are not properties of the
  // context's global object and so are fetched by name.
  card: vm.runInContext(
    "({ VIZ, SEQ, fmt, resolveColor, toDay, today, dayAfter, fmtDay, activeOn, changelog, spread, layout, esc })",
    ctx
  ),

  // Values built inside the vm have that realm's prototypes, which deepEqual
  // rejects; a JSON round trip brings them into this one.
  plain: (v) => JSON.parse(JSON.stringify(v)),

  // Sets the local date the card sees as today, at midday.
  setToday: (day) => {
    ctx.__now = day + "T12:00:00";
  },

  // A new card element with `config` applied.
  make: (config) => {
    const el = new ctx.customElements.cls();
    el.setConfig(config);
    return el;
  },
};
