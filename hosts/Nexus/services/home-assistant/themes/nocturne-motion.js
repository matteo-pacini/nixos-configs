// Nocturne "Lacquer" motion for Home Assistant dashboards.
//
// The theme (nocturne.yaml) carries what CSS alone can do: cards rising in,
// the hover lift and the sheen. This module adds what needs to see a value
// change: numbers that count to their new value, a ring from the icon when a
// state changes, a slow glow on icons in the alert (red) state, gliding
// sliders and gauges, and a press effect for touch screens.
//
// Design system: https://claude.ai/artifact/LE95HYdwkCBnrbFUE9pvKY (Motion section)
// Motion study:  https://claude.ai/artifact/N6fbU7Mxn4jxovYGMmQ8YU
//
// It works by wrapping Lit's firstUpdated on a few HA and mushroom elements
// and adding a stylesheet to their shadow roots. Element and class names are
// HA/mushroom internals, so a frontend update can silently turn an effect
// off; nothing here can break a card, because every hook is wrapped in
// try/catch and only adds styles or rewrites text Lit has already set.

const EASE = "cubic-bezier(.2, .8, .2, 1)";
const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");

function sheet(css) {
  const s = new CSSStyleSheet();
  s.replaceSync(css);
  return s;
}

function adopt(root, s) {
  if (root && !root.adoptedStyleSheets.includes(s)) {
    root.adoptedStyleSheets = [...root.adoptedStyleSheets, s];
  }
}

// Finds elements across shadow roots; used once per tag for instances that
// connected before this module loaded.
function deepQuery(tag, root = document, out = []) {
  for (const el of root.querySelectorAll("*")) {
    if (el.localName === tag) out.push(el);
    if (el.shadowRoot) deepQuery(tag, el.shadowRoot, out);
  }
  return out;
}

function hook(tag, fn) {
  const seen = new WeakSet();
  const run = (el) => {
    if (seen.has(el)) return;
    seen.add(el);
    try {
      fn(el);
    } catch (err) {
      console.warn("[nocturne-motion]", tag, err);
    }
  };
  customElements.whenDefined(tag).then(() => {
    // Not connectedCallback: the registry copies lifecycle callbacks when the
    // element is defined, so patching it afterwards never runs. Lit looks up
    // firstUpdated on every element, after its first render, and an adopted
    // sheet stays in the shadow root across reconnects.
    const proto = customElements.get(tag).prototype;
    const orig = proto.firstUpdated;
    proto.firstUpdated = function (...args) {
      if (orig) orig.apply(this, args);
      run(this);
    };
    deepQuery(tag).forEach(run);
  });
}

// ---- Icons: ring on state change, glow while red --------------------------

const iconSheet = sheet(`
  .container { transition: box-shadow 280ms ${EASE}; }
  :host(.nc-bloom) .container { animation: nc-bloom 900ms ${EASE}; }
  :host(.nc-alert) .container { animation: nc-breathe 3.2s ease-in-out infinite; }
  @keyframes nc-bloom {
    from { box-shadow: 0 0 0 0 color-mix(in srgb, var(--tile-icon-color) 60%, transparent); }
    to { box-shadow: 0 0 0 14px transparent; }
  }
  @keyframes nc-breathe {
    0%, 100% { box-shadow: 0 0 0 0 transparent; }
    50% { box-shadow: 0 0 22px color-mix(in srgb, var(--tile-icon-color) 50%, transparent); }
  }
  @media (prefers-reduced-motion: reduce) {
    :host(.nc-bloom) .container, :host(.nc-alert) .container { animation: none; }
  }
`);

function iconColor(el) {
  return getComputedStyle(el).getPropertyValue("--tile-icon-color").trim();
}

function redColor() {
  return getComputedStyle(document.documentElement).getPropertyValue("--red-color").trim();
}

hook("ha-tile-icon", (el) => {
  adopt(el.shadowRoot, iconSheet);
  let last = iconColor(el);
  el.classList.toggle("nc-alert", last !== "" && last === redColor());
  // Cards set the colour through the style attribute (mushroom) or
  // data-state (tile), so either one changing is a state change.
  new MutationObserver(() => {
    const now = iconColor(el);
    if (now === last) return;
    last = now;
    el.classList.toggle("nc-alert", now === redColor());
    el.classList.remove("nc-bloom");
    void el.offsetWidth;
    el.classList.add("nc-bloom");
  }).observe(el, { attributes: true, attributeFilter: ["style", "data-state", "class"] });
  el.addEventListener("animationend", (e) => {
    if (e.animationName === "nc-bloom") el.classList.remove("nc-bloom");
  });
});

// ---- Numbers count to their new value ---------------------------------------

const NUM = /-?\d+(?:[.,]\d+)?/g;

function parse(text) {
  const nums = text.match(NUM);
  if (!nums) return null;
  return {
    shape: text.replace(NUM, "#"),
    values: nums.map((n) => parseFloat(n.replace(",", "."))),
    decimals: nums.map((n) => (n.split(/[.,]/)[1] || "").length),
    comma: nums.map((n) => n.includes(",")),
  };
}

function format(p, values) {
  let i = 0;
  return p.shape.replace(/#/g, () => {
    const s = values[i].toFixed(p.decimals[i]);
    return p.comma[i++] ? s.replace(".", ",") : s;
  });
}

// Watches the elements `targets()` returns and, when one's text changes
// between two strings with the same shape ("Water 98%" -> "Water 97%"),
// replays the change as a count. The final frame writes exactly the text the
// card rendered, and our own writes are dropped with takeRecords so they
// don't re-trigger the observer.
function countText(root, targets) {
  const shown = new WeakMap();
  const running = new WeakMap();
  const textNode = (el) => [...el.childNodes].find((n) => n.nodeType === Node.TEXT_NODE && /\d/.test(n.data));
  for (const el of targets()) shown.set(el, el.textContent);

  const observer = new MutationObserver(() => {
    for (const el of targets()) {
      const before = shown.get(el);
      const after = el.textContent;
      shown.set(el, after);
      if (before === undefined || before === after || reduced.matches || document.hidden) continue;
      const from = parse(before);
      const to = parse(after);
      const node = textNode(el);
      if (!from || !to || from.shape !== to.shape || !node || node.data !== after) continue;
      cancelAnimationFrame(running.get(el));
      const t0 = performance.now();
      const step = (now) => {
        const k = Math.min(1, (now - t0) / 700);
        const e = 1 - Math.pow(1 - k, 3);
        node.data = k < 1 ? format(to, to.values.map((v, i) => from.values[i] + (v - from.values[i]) * e)) : after;
        observer.takeRecords();
        if (k < 1) running.set(el, requestAnimationFrame(step));
      };
      running.set(el, requestAnimationFrame(step));
    }
  });
  observer.observe(root, { subtree: true, childList: true, characterData: true });
}

// ha-tile-info renders the primary and secondary lines from spans slotted in
// by the card (mushroom template card and the tile card both use it).
hook("ha-tile-info", (el) => countText(el, () => el.children));

// ---- Gauges: Lacquer curve on the arc, counting value -----------------------

const gaugeSheet = sheet(`
  .value { transition: stroke-dashoffset 900ms ${EASE}, stroke 400ms ease; }
`);
hook("ha-gauge", (el) => {
  adopt(el.shadowRoot, gaugeSheet);
  countText(el.shadowRoot, () => el.shadowRoot.querySelectorAll("text.value-text"));
});

// ---- Sliders glide ----------------------------------------------------------

// The slider turns its transition off while dragged (.controlled, which is
// more specific than these rules), so this only slows down value changes
// that come from elsewhere.
const mushroomSlider = sheet(`
  .slider .slider-track-active,
  .slider .slider-track-indicator {
    transition-duration: 600ms;
    transition-timing-function: ${EASE};
  }
`);
hook("mushroom-slider", (el) => adopt(el.shadowRoot, mushroomSlider));

// ---- Press effect on touch screens ------------------------------------------

// Pointer devices get the theme's hover lift instead; a scale on :active
// would fight it.
const pressSheet = sheet(`
  @media (hover: none) and (prefers-reduced-motion: no-preference) {
    :host { transition: transform 280ms ${EASE}; }
    :host(:active) { transform: scale(0.97); transition-duration: 90ms; }
  }
`);
hook("ha-card", (el) => adopt(el.shadowRoot, pressSheet));
