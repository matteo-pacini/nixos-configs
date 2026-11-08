// nocturne-floorplan: a flat, layered house plan for Home Assistant.
//
// One card shows one floor at a time with three layers: lights (tap a bulb to
// switch it, tap a room to switch all of its lights, hold a bulb for its
// dialog; a dimmed bulb is amber, a full one yellow), heat (a "current /
// target" pill per room, current green at or above target and red below,
// orange with a flame while the radiator heats, and a humidity pill beside
// it) and doors (green closed, red open).
//
// The card only draws; the house lives in the card's YAML, so the layout and
// entity ids stay in .storage rather than this repository. Coordinates are
// percent of the floor's width (x) and height (y); `width` sets the floor's
// aspect ratio (the plan is width x 1000 SVG units).
//
//   type: custom:nocturne-floorplan
//   title: House
//   layers: [lights, heat, doors]    # on when the card loads (default: all)
//   floors:
//     - name: Ground
//       width: 1797
//       x0: -21                      # optional: draw left of 0 (detached rooms)
//       y0: -9                       # optional: draw above 0 (names outside)
//       labels: [{ text: Patio, at: [-2.8, 30.5], rotate: -90 }]
//       rooms:
//         - name: Kitchen
//           poly: [[5.6, 4.9], [45.5, 4.9], ...]
//           label: [8, 11]
//           label_arrow: [[51, -2], [51, 4]]  # optional: from, to (wide only)
//           pill: [25, 40]           # centre of the temperature pill
//           humidity_pill: [28, 39]  # optional; default is under the first
//           narrow_pill: [62, 49.9]  # optional: pill position on phones (below)
//           temperature: sensor.kitchen_temperature
//           humidity: sensor.kitchen_humidity
//           climate: climate.kitchen_radiator   # target and heating
//           lights: [{ entity: switch.kitchen_1, at: [21, 60] }]  # at: default room centre;
//                                       # narrow_at: optional position on phones
//           stairs: [46.5, 24, 55.4, 54.8]      # optional: x0, y0, x1, y1
//           shell: [-21, 8.3, -5.6, 52.7]       # optional: its own outline
//       doors: [{ entity: binary_sensor.main_door, a: [47.6, 97.6], b: [54.8, 97.6] }]
//
// Below NARROW px of card width (phones) the plan is turned a quarter
// anticlockwise so a wide floor fills the portrait screen: what is left on the
// plan (the garage) ends up at the bottom, and text stays upright. Room names
// then sit at each room's top-left corner, and a room can move its pills for
// this view with `narrow_pill` / `narrow_humidity_pill`, and a light with
// `narrow_at` (same coordinates as the rest, before turning); without them the pills keep their usual place
// and the humidity pill goes under the temperature one.
//
// Design system: https://claude.ai/artifact/LE95HYdwkCBnrbFUE9pvKY
// Floorplan drafts (draft A): https://claude.ai/artifact/LFWSboBTmE83nFT9kYynnc

const MDI = {
  bulb: "M12,2A7,7 0 0,0 5,9C5,11.38 6.19,13.47 8,14.74V17A1,1 0 0,0 9,18H15A1,1 0 0,0 16,17V14.74C17.81,13.47 19,11.38 19,9A7,7 0 0,0 12,2M9,21A1,1 0 0,0 10,22H14A1,1 0 0,0 15,21V20H9V21Z",
  bulbOff: "M12,2A7,7 0 0,1 19,9C19,11.38 17.81,13.47 16,14.74V17A1,1 0 0,1 15,18H9A1,1 0 0,1 8,17V14.74C6.19,13.47 5,11.38 5,9A7,7 0 0,1 12,2M9,21V20H15V21A1,1 0 0,1 14,22H10A1,1 0 0,1 9,21M12,4A5,5 0 0,0 7,9C7,11.05 8.23,12.81 10,13.58V16H14V13.58C15.77,12.81 17,11.05 17,9A5,5 0 0,0 12,4Z",
  fire: "M17.66 11.2C17.43 10.9 17.15 10.64 16.89 10.38C16.22 9.78 15.46 9.35 14.82 8.72C13.33 7.26 13 4.85 13.95 3C13 3.23 12.17 3.75 11.46 4.32C8.87 6.4 7.85 10.07 9.07 13.22C9.11 13.32 9.15 13.42 9.15 13.55C9.15 13.77 9 13.97 8.8 14.05C8.57 14.15 8.33 14.09 8.14 13.93C8.08 13.88 8.04 13.83 8 13.76C6.87 12.33 6.69 10.28 7.45 8.64C5.78 10 4.87 12.3 5 14.47C5.06 14.97 5.12 15.47 5.29 15.97C5.43 16.57 5.7 17.17 6 17.7C7.08 19.43 8.95 20.67 10.96 20.92C13.1 21.19 15.39 20.8 17.03 19.32C18.86 17.66 19.5 15 18.56 12.72L18.43 12.46C18.22 12 17.66 11.2 17.66 11.2M14.5 17.5C14.22 17.74 13.76 18 13.4 18.1C12.28 18.5 11.16 17.94 10.5 17.28C11.69 17 12.4 16.12 12.61 15.23C12.78 14.43 12.46 13.77 12.33 13C12.21 12.26 12.23 11.63 12.5 10.94C12.69 11.32 12.89 11.7 13.13 12C13.9 13 15.11 13.44 15.37 14.8C15.41 14.94 15.43 15.08 15.43 15.23C15.46 16.05 15.1 16.95 14.5 17.5H14.5Z",
  water: "M12,20A6,6 0 0,1 6,14C6,10 12,3.25 12,3.25C12,3.25 18,10 18,14A6,6 0 0,1 12,20Z",
};

const LAYERS = [
  { id: "lights", name: "Lights", icon: "mdi:lightbulb", color: "var(--yellow-color)" },
  { id: "heat", name: "Heat", icon: "mdi:radiator", color: "var(--orange-color)" },
  { id: "doors", name: "Doors", icon: "mdi:door-open", color: "var(--red-color)" },
];

// Pill text is set in the code face, which is monospaced, so its width is
// known without measuring (and measuring returns 0 while the view is hidden).
const PILL_FONT = 32;
const CHAR = PILL_FONT * 0.6;
const PAD = 22;
const ICON = 32;
const GAP = 8;
const HOLD_MS = 500;
const NARROW = 500;
// Text, pills and bulbs are drawn at a scale k. Wide, k grows with the
// plan's width in SVG units (1 up to ZOOM_UNITS), so text is the same size
// on every floor and stays readable on a wide floor. Turned, the plan is
// always 1040 units wide, so k is fixed.
const ZOOM_UNITS = 1550;
const ZOOM_NARROW = 1.15;

const CSS = `
  :host {
    /* Block, not the default inline: ResizeObserver reports an inline box
       as 0 wide, and the narrow layout depends on it. */
    display: block;
    --fp-void: var(--primary-background-color);
    --fp-raised: var(--input-fill-color, var(--secondary-background-color));
    --fp-card: var(--ha-card-background, var(--card-background-color));
    --fp-line: var(--divider-color);
    --fp-muted: var(--secondary-text-color);
    --fp-faint: var(--disabled-text-color);
    --fp-ease: cubic-bezier(.2, .8, .2, 1);
  }
  ha-card { overflow: hidden; }
  .head { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; padding: 14px 16px 0; }
  .head h2 { margin: 0; display: flex; align-items: center; gap: 8px; font-family: var(--ha-font-family-heading, inherit); font-size: 16px; font-weight: 600; }
  .head h2 ha-icon { --mdc-icon-size: 18px; color: var(--fp-muted); }
  /* The selection is one pill behind the buttons that glides to the chosen
     floor; the header is kept between renders so the transition can run. */
  .seg { position: relative; display: inline-grid; grid-auto-flow: column; grid-auto-columns: 1fr; padding: 3px; border-radius: 999px; background: var(--fp-raised); margin-left: auto; }
  .seg::before { content: ""; position: absolute; top: 3px; bottom: 3px; left: 3px; width: calc((100% - 6px) / var(--n)); border-radius: 999px; background: var(--primary-color); transform: translateX(calc(100% * var(--i, 0))); transition: transform 280ms var(--fp-ease); }
  button { all: unset; cursor: pointer; box-sizing: border-box; }
  button:focus-visible, [role="button"]:focus-visible { outline: 2px solid var(--accent-color); outline-offset: 2px; }
  .seg button { position: relative; padding: 0 12px; line-height: 28px; text-align: center; border-radius: 999px; font-size: 12px; font-weight: 600; color: var(--fp-muted); transition: color 280ms var(--fp-ease); }
  .seg button[aria-pressed="true"] { color: var(--text-primary-color); }
  @media (prefers-reduced-motion: reduce) { .seg::before, .seg button { transition: none; } }
  .layers { display: flex; gap: 6px; flex-wrap: wrap; padding: 10px 16px 0; }
  .chip { display: inline-flex; align-items: center; gap: 6px; height: 30px; padding: 0 12px 0 8px; border-radius: 999px; background: var(--fp-raised); font-size: 12px; font-weight: 600; color: var(--fp-muted); transition: background .25s ease, color .25s ease, box-shadow .25s ease; }
  .chip ha-icon { --mdc-icon-size: 16px; }
  .chip .n { font-family: var(--ha-font-family-code, monospace); font-weight: 500; }
  .chip[aria-pressed="true"] { color: var(--primary-text-color); background: color-mix(in srgb, var(--c) 16%, var(--fp-raised)); box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--c) 45%, transparent); }
  .chip[aria-pressed="true"] ha-icon { color: var(--c); }
  .plan { padding: 12px 16px 16px; }
  svg { display: block; width: 100%; height: auto; -webkit-tap-highlight-color: transparent; }

  .shell { fill: var(--fp-void); }
  .room .fill { fill: var(--fp-raised); stroke: var(--fp-void); stroke-width: 10; stroke-linejoin: round; transition: fill .35s ease; }
  .room.lit .fill { fill: color-mix(in srgb, var(--yellow-color) 8%, var(--fp-raised)); }
  .room .glow { opacity: 0; pointer-events: none; }
  .room.lit .glow.on { opacity: 1; }
  .arrow { fill: none; stroke: var(--fp-muted); stroke-width: calc(4px * var(--k)); stroke-linecap: round; stroke-linejoin: round; pointer-events: none; }
  .room .name, .label { fill: var(--fp-muted); font-family: var(--ha-font-family-body, inherit); font-size: calc(32px * var(--k)); font-weight: 600; letter-spacing: .05em; text-transform: uppercase; pointer-events: none; }
  .label { font-size: calc(26px * var(--k)); letter-spacing: .3em; opacity: .6; }
  .room.tappable { cursor: pointer; }
  @media (hover: hover) {
    .room.tappable:hover .fill { fill: color-mix(in srgb, var(--fp-raised) 82%, var(--primary-color)); }
    .bulb:hover circle { stroke: var(--yellow-color); }
  }
  .stairs line { stroke: var(--fp-line); stroke-width: 4; }
  .bulb { cursor: pointer; }
  .bulb circle { fill: var(--fp-card); stroke: var(--fp-line); stroke-width: 3; transition: fill .3s ease, stroke .3s ease; }
  .bulb path { fill: var(--fp-faint); transition: fill .3s ease; }
  .bulb.on circle { fill: var(--bulb); stroke: var(--bulb); }
  .bulb.on path { fill: var(--text-primary-color); }
  .bulb.na { opacity: .4; }
  .bulb text { fill: var(--primary-text-color); font-family: var(--ha-font-family-code, monospace); font-size: 34px; font-weight: 500; }
  .pill { cursor: pointer; }
  .pill rect { fill: var(--fp-card); stroke: var(--fp-line); stroke-width: 3; transition: fill .3s ease, stroke .3s ease; }
  .pill text { font-family: var(--ha-font-family-code, monospace); font-size: ${PILL_FONT}px; font-weight: 500; fill: var(--primary-text-color); }
  .pill .sep, .pill .tgt { fill: var(--fp-muted); }
  .pill.ok .now { fill: var(--green-color); }
  .pill.low .now { fill: var(--red-color); }
  .pill.heat rect { fill: color-mix(in srgb, var(--orange-color) 18%, var(--fp-card)); stroke: color-mix(in srgb, var(--orange-color) 55%, transparent); }
  .pill.heat .tgt, .pill path { fill: var(--orange-color); }
  .pill.rh path { fill: var(--cyan-color); }
  .door { stroke-width: 18; stroke-linecap: round; transition: stroke .3s ease; }
  .door.closed { stroke: var(--green-color); }
  .door.open { stroke: var(--red-color); }
  .door.na { stroke: var(--fp-faint); }
`;

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const num = (st) => (st && st.state !== "" && !isNaN(Number(st.state)) ? Number(st.state) : null);

class NocturneFloorplan extends HTMLElement {
  setConfig(config) {
    if (!Array.isArray(config.floors) || !config.floors.length) {
      throw new Error("nocturne-floorplan: `floors` needs at least one floor");
    }
    this._config = config;
    this._floor = 0;
    this._layers = new Set(config.layers || LAYERS.map((l) => l.id));
    this._entities = this._collect();
    this._seen = null;
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => this._click(e));
      this.shadowRoot.addEventListener("keydown", (e) => {
        if ((e.key === "Enter" || e.key === " ") && e.target.closest("[role=button]")) {
          e.preventDefault();
          this._click(e);
        }
      });
      this.shadowRoot.addEventListener("pointerdown", (e) => this._holdStart(e));
      for (const t of ["pointerup", "pointercancel"]) {
        this.shadowRoot.addEventListener(t, () => clearTimeout(this._holdTimer));
      }
    }
    this._render();
  }

  connectedCallback() {
    this._resize = this._resize || new ResizeObserver(([e]) => {
      const narrow = e.contentRect.width > 0 && e.contentRect.width < NARROW;
      if (narrow !== this._narrow) {
        this._narrow = narrow;
        this._render();
      }
    });
    this._resize.observe(this);
  }

  disconnectedCallback() {
    this._resize?.disconnect();
  }

  set hass(hass) {
    this._hass = hass;
    // Redraw only when one of this card's entities changed; hass is set on
    // every state change in the house.
    const seen = this._entities.map((id) => hass.states[id]);
    if (this._seen && seen.every((s, i) => s === this._seen[i])) return;
    this._seen = seen;
    this._render();
  }

  getCardSize() {
    return 8;
  }

  getGridOptions() {
    return { columns: "full" };
  }

  _collect() {
    const ids = new Set();
    for (const f of this._config.floors) {
      for (const r of f.rooms || []) {
        for (const k of ["temperature", "humidity", "climate"]) if (r[k]) ids.add(r[k]);
        for (const l of r.lights || []) ids.add(l.entity);
      }
      for (const d of f.doors || []) ids.add(d.entity);
    }
    return [...ids];
  }

  _st(id) {
    return id && this._hass ? this._hass.states[id] : undefined;
  }

  _on(id) {
    return this._st(id)?.state === "on";
  }

  _heat(room) {
    const c = this._st(room.climate);
    const now = num(this._st(room.temperature)) ?? (c ? Number(c.attributes.current_temperature) : null);
    const target = c && c.state !== "off" && c.attributes.temperature != null ? Number(c.attributes.temperature) : null;
    return { now: Number.isFinite(now) ? now : null, target, heating: c?.attributes.hvac_action === "heating", off: c?.state === "off" };
  }

  _counts() {
    const all = (fn) => this._config.floors.flatMap(fn);
    return {
      lights: all((f) => (f.rooms || []).flatMap((r) => r.lights || [])).filter((l) => this._on(l.entity)).length + " on",
      heat: all((f) => f.rooms || []).filter((r) => r.climate && this._heat(r).heating).length + " heating",
      doors: all((f) => f.doors || []).filter((d) => this._on(d.entity)).length + " open",
    };
  }

  _render() {
    if (!this.shadowRoot || !this._config) return;
    const c = this._config;
    const counts = this._counts();
    const floors = c.floors.length > 1
      ? `<div class="seg" role="group" aria-label="Floor" style="--n: ${c.floors.length}">${c.floors.map((f, i) => `<button type="button" data-floor="${i}">${esc(f.name)}</button>`).join("")}</div>`
      : "";
    const chips = LAYERS.map((l) => `<button class="chip" type="button" data-layer="${l.id}" aria-pressed="${this._layers.has(l.id)}" style="--c: ${l.color}"><ha-icon icon="${l.icon}"></ha-icon>${l.name} <span class="n">${counts[l.id]}</span></button>`).join("");
    // ha-card is created once and only its contents are replaced: a new
    // ha-card would replay the theme's rise-in animation on every update.
    if (!this._parts) {
      this.shadowRoot.innerHTML = `<style>${CSS}</style><ha-card><div class="head"></div><div class="layers" role="group" aria-label="Layers"></div><div class="plan"></div></ha-card>`;
      const q = (sel) => this.shadowRoot.querySelector(sel);
      this._parts = { head: q(".head"), layers: q(".layers"), plan: q(".plan") };
    }
    const head = `<h2><ha-icon icon="${esc(c.icon || "mdi:home")}"></ha-icon>${esc(c.title || "House")}</h2>${floors}`;
    if (head !== this._head) {
      this._parts.head.innerHTML = this._head = head;
    }
    const seg = this._parts.head.querySelector(".seg");
    if (seg) {
      seg.style.setProperty("--i", this._floor);
      seg.querySelectorAll("button").forEach((b, i) => b.setAttribute("aria-pressed", i === this._floor));
    }
    this._parts.layers.innerHTML = chips;
    this._parts.plan.innerHTML = this._plan(c.floors[this._floor]);
  }

  _plan(floor) {
    const W = floor.width || 1000;
    const X0 = ((floor.x0 || 0) * W) / 100;
    const turn = this._narrow;
    // Floor percent to SVG units; turned, (x, y) becomes (y, W - x).
    const px = (p) => {
      const x = (p[0] * W) / 100;
      const y = p[1] * 10;
      return turn ? [y, W - x] : [x, y];
    };
    const rect = (b, cls) => {
      const [a, c] = [px([b[0], b[1]]), px([b[2], b[3]])];
      return `<rect class="${cls}" x="${Math.min(a[0], c[0])}" y="${Math.min(a[1], c[1])}" width="${Math.abs(c[0] - a[0])}" height="${Math.abs(c[1] - a[1])}" rx="28"/>`;
    };
    // y0 only widens the wide view: turned, room names are placed inside
    // their rooms and labels outside the house are not drawn.
    const Y0 = turn ? 0 : (floor.y0 || 0) * 10;
    const view = turn ? [-20, -20, 1040, W - X0 + 40] : [X0 - 20, Y0 - 20, W - X0 + 40, 1040 - Y0];
    const k = turn ? ZOOM_NARROW : Math.max(1, view[2] / ZOOM_UNITS);
    const at = (r, key) => (turn && r[`narrow_${key}`]) || (key === "humidity_pill" && turn ? null : r[key]);
    const pts = (poly) => poly.map((p) => px(p).join(",")).join(" ");
    const on = (l) => this._layers.has(l);
    const spot = (l, r) => (turn && l.narrow_at) || l.at || centre(r.poly);
    const rooms = floor.rooms || [];
    const name = (id, fallback) => esc(this._st(id)?.attributes.friendly_name || fallback || id);
    const uid = Math.random().toString(36).slice(2, 8);

    const tint = (id) => {
      const st = this._st(id);
      const b = st?.attributes.brightness;
      return b == null ? "var(--yellow-color)" : `color-mix(in srgb, var(--yellow-color) ${Math.round(b / 2.55)}%, var(--orange-color))`;
    };
    const glows = rooms.flatMap((r) => r.lights || []);

    let s = `<svg viewBox="${view.join(" ")}" style="--k: ${k}" role="img" aria-label="${esc(floor.name)} plan">`;
    // One glow per light: a dimmed light glows amber, a full one yellow.
    s += `<defs>${glows.map((l, j) => `<radialGradient id="g${uid}-${j}"><stop offset="0" style="stop-color: ${tint(l.entity)}" stop-opacity=".42"/><stop offset="1" style="stop-color: ${tint(l.entity)}" stop-opacity="0"/></radialGradient>`).join("")}`;
    rooms.forEach((r, i) => (s += `<clipPath id="c${uid}-${i}"><polygon points="${pts(r.poly)}"/></clipPath>`));
    s += `</defs>${rect([0, 0, 100, 100], "shell")}`;
    for (const r of rooms) if (r.shell) s += rect(r.shell, "shell");
    for (const l of floor.labels || []) {
      const a = px(l.at);
      s += `<text class="label" text-anchor="middle" dominant-baseline="middle" transform="translate(${a[0]},${a[1]}) rotate(${(l.rotate || 0) + (turn ? 90 : 0)})">${esc(l.text)}</text>`;
    }

    rooms.forEach((r, i) => {
      const lights = r.lights || [];
      const lit = on("lights") && lights.some((l) => this._on(l.entity));
      const tap = on("lights") && lights.length;
      s += `<g class="room${lit ? " lit" : ""}${tap ? " tappable" : ""}"${tap ? ` data-room="${i}" role="button" tabindex="0" aria-label="Switch ${esc(r.name)} lights"` : ""}>`;
      s += `<polygon class="fill" points="${pts(r.poly)}"/>`;
      if (on("lights")) {
        for (const l of lights) {
          const c = px(spot(l, r));
          s += `<circle class="glow${this._on(l.entity) ? " on" : ""}" clip-path="url(#c${uid}-${i})" cx="${c[0]}" cy="${c[1]}" r="300" fill="url(#g${uid}-${glows.indexOf(l)})"/>`;
        }
      }
      if (r.stairs) {
        // Treads run across the stairs every 44 units, inset 24 at each end.
        const [x0, y0, x1, y1] = r.stairs;
        const inset = (24 / W) * 100;
        s += `<g class="stairs">`;
        for (let y = y0; y < y1 - 2; y += 4.4) {
          const [a, b] = [px([x0 + inset, y]), px([x1 - inset, y])];
          s += `<line x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}"/>`;
        }
        s += `</g>`;
      }
      if (r.label) {
        // Turned, the configured corner is no longer the top-left one.
        const pts = r.poly.map(px);
        const l = turn ? [Math.min(...pts.map((p) => p[0])) + 24, Math.min(...pts.map((p) => p[1])) + 24 + 32 * k] : px(r.label);
        s += `<text class="name" x="${l[0]}" y="${l[1]}">${esc(r.name)}</text>`;
        if (!turn && r.label_arrow) {
          const [a, b] = r.label_arrow.map(px);
          const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
          const [ux, uy] = [(b[0] - a[0]) / len, (b[1] - a[1]) / len];
          const h = 14 * k;
          const barb = (side) => `${b[0] - h * ux + side * h * uy},${b[1] - h * uy - side * h * ux}`;
          s += `<path class="arrow" d="M${a} L${b} M${barb(1)} L${b} L${barb(-1)}"/>`;
        }
      }
      s += `</g>`;
    });

    if (on("doors")) {
      for (const d of floor.doors || []) {
        const st = this._st(d.entity);
        const cls = !st || st.state === "unavailable" ? "na" : st.state === "on" ? "open" : "closed";
        const [a, b] = [px(d.a), px(d.b)];
        s += `<line class="door ${cls}" x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}"><title>${name(d.entity)}: ${cls === "na" ? "unavailable" : cls}</title></line>`;
      }
    }

    if (on("lights")) {
      for (const r of rooms) {
        for (const l of r.lights || []) {
          const st = this._st(l.entity);
          const lon = st?.state === "on";
          const na = !st || st.state === "unavailable";
          const b = lon && st.attributes.brightness != null ? Math.round(st.attributes.brightness / 2.55) : null;
          const c = px(spot(l, r));
          // Dimmable lights go from amber at low brightness to yellow at full.
          s += `<g class="bulb${lon ? " on" : ""}${na ? " na" : ""}" style="--bulb: ${tint(l.entity)}" data-entity="${esc(l.entity)}" role="button" tabindex="0" aria-label="${name(l.entity)} ${lon ? "on" : "off"}" transform="translate(${c[0]},${c[1]}) scale(${k})"><circle r="58"/><path transform="translate(-34,-34) scale(2.8333)" d="${lon ? MDI.bulb : MDI.bulbOff}"/>${b != null ? `<text y="104" text-anchor="middle">${b}%</text>` : ""}</g>`;
        }
      }
    }

    if (on("heat")) {
      for (const r of rooms) {
        const pill = at(r, "pill");
        if (!pill) continue;
        const h = this._heat(r);
        const more = esc(r.climate || r.temperature || r.humidity);
        if (h.now != null) {
          const cls = h.target == null ? "" : h.now >= h.target ? " ok" : " low";
          const tgt = r.climate ? (h.off ? "off" : h.target != null ? `${h.target}°` : null) : null;
          const label = `${h.now.toFixed(1)}°` + (tgt ? ` / ${tgt}` : "");
          s += this._pill(px(pill), k, `pill${h.heating ? " heat" : ""}${cls}`, more, h.heating ? MDI.fire : null, label,
            `<tspan class="now">${h.now.toFixed(1)}°</tspan>${tgt ? `<tspan class="sep"> / </tspan><tspan class="tgt">${tgt}</tspan>` : ""}`,
            `${esc(r.name)}: ${h.now.toFixed(1)}° now${h.target != null ? `, target ${h.target}°` : ""}${h.heating ? ", heating" : ""}`);
        }
        const rh = num(this._st(r.humidity));
        if (rh != null) {
          const hp = at(r, "humidity_pill");
          const c = hp ? px(hp) : [px(pill)[0], px(pill)[1] + 64 * k];
          const text = `${Math.round(rh)}%`;
          s += this._pill(c, k, "pill rh", esc(r.humidity), MDI.water, text, text, `${esc(r.name)}: ${text} relative humidity`);
        }
      }
    }
    return s + "</svg>";
  }

  // A pill centred on `c` and scaled by `k`, sized to its text so the padding matches on both
  // sides. `label` is the plain text (for the width), `body` its marked-up form.
  _pill(c, k, cls, entity, icon, label, body, title) {
    const lead = icon ? ICON + GAP : 0;
    const w = PAD * 2 + lead + label.length * CHAR;
    return `<g class="${cls}" data-more="${entity}" role="button" tabindex="0" aria-label="${title}" transform="translate(${c[0]},${c[1]}) scale(${k}) translate(${-w / 2},-28)"><title>${title}</title><rect width="${w}" height="56" rx="28"/>${icon ? `<path transform="translate(${PAD},12) scale(1.3333)" d="${icon}"/>` : ""}<text x="${PAD + lead}" y="39">${body}</text></g>`;
  }

  _click(e) {
    if (this._held) {
      this._held = false;
      return;
    }
    const t = e.target.closest("[data-floor],[data-layer],[data-entity],[data-more],[data-room]");
    if (!t) return;
    if (t.dataset.floor) {
      const floor = Number(t.dataset.floor);
      if (floor === this._floor) return;
      this._floor = floor;
      this._render();
      if (!matchMedia("(prefers-reduced-motion: reduce)").matches) {
        this._parts.plan.animate([{ opacity: 0, transform: "translateY(8px)" }, { opacity: 1, transform: "none" }], { duration: 280, easing: "cubic-bezier(.2, .8, .2, 1)" });
      }
      return;
    } else if (t.dataset.layer) {
      const l = t.dataset.layer;
      this._layers.has(l) ? this._layers.delete(l) : this._layers.add(l);
    } else if (t.dataset.entity) {
      this._hass.callService("homeassistant", "toggle", { entity_id: t.dataset.entity });
      return;
    } else if (t.dataset.more) {
      this._moreInfo(t.dataset.more);
      return;
    } else if (t.dataset.room) {
      const ids = this._config.floors[this._floor].rooms[Number(t.dataset.room)].lights.map((l) => l.entity);
      const service = ids.some((id) => this._on(id)) ? "turn_off" : "turn_on";
      this._hass.callService("homeassistant", service, { entity_id: ids });
      return;
    }
    this._render();
  }

  // Holding a bulb opens its dialog (brightness), as a tile card's hold does.
  _holdStart(e) {
    this._held = false;
    clearTimeout(this._holdTimer);
    const t = e.target.closest("[data-entity]");
    if (!t) return;
    this._holdTimer = setTimeout(() => {
      this._held = true;
      this._moreInfo(t.dataset.entity);
    }, HOLD_MS);
  }

  _moreInfo(entityId) {
    this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId }, bubbles: true, composed: true }));
  }
}

// Centre of a room's main body: the bounding box of its first four points
// (rooms are traced starting with their largest rectangle), stretched down to
// the polygon's lowest point.
function centre(poly) {
  const xs = poly.slice(0, 4).map((p) => p[0]);
  const ys = poly.map((p) => p[1]);
  return [(Math.min(...xs) + Math.max(...xs)) / 2, (Math.min(...poly.slice(0, 4).map((p) => p[1])) + Math.max(...ys)) / 2];
}

customElements.define("nocturne-floorplan", NocturneFloorplan);
window.customCards = window.customCards || [];
window.customCards.push({
  type: "nocturne-floorplan",
  name: "Nocturne floorplan",
  description: "Layered house plan: lights, heating pills and doors.",
});
