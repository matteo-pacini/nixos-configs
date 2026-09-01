// Budget sankey card.
//
// Ported from the Claude Design document "FFD49 Budget.dc.html". The original
// ran on Claude Design's own <x-dc>/DCLogic/<sc-for> runtime, which is a build
// artefact of that editor rather than a published library, so the layout maths
// were lifted verbatim and the templating replaced with plain DOM. The Dracula
// palette is inlined from the Ledger design system's tokens/colors.css.
//
// The card renders one three-level sankey: root -> group -> line item. It holds
// no Home Assistant state; every figure comes from the card's own config, which
// is edited through the Lovelace raw editor and lives in .storage. That is
// deliberate: the figures are household finances and this repository is public,
// so only the renderer is version controlled, never the numbers.

const VIZ = {
  bg: "#21222c",
  card: "#282a36",
  raised: "#2f313f",
  borderSubtle: "#343746",
  borderStrong: "#565973",
  textPrimary: "#f8f8f2",
  textSecondary: "#b9bcd0",
  textMuted: "#6272a4",
  moneyOut: "#ff5555",
  moneyIn: "#50fa7b",
  pending: "#ffb86c",
  accent: "#bd93f9",
  shadow1: "0 1px 2px rgba(15,16,22,.5)",
  seq: ["#bd93f9", "#8be9fd", "#ff79c6", "#50fa7b", "#ffb86c", "#f1fa8c", "#ff5555", "#6272a4"],
};
// Original authored order: viz-5, viz-2, viz-3, viz-4, viz-1, viz-6, viz-7, viz-8.
const SEQ = [VIZ.seq[4], VIZ.seq[1], VIZ.seq[2], VIZ.seq[3], VIZ.seq[0], VIZ.seq[5], VIZ.seq[6], VIZ.seq[7]];

const FONT_DISPLAY = '"Space Grotesk","Helvetica Neue",sans-serif';
const FONT_BODY = '"IBM Plex Sans","Helvetica Neue",sans-serif';
const FONT_MONO = '"JetBrains Mono","SFMono-Regular",ui-monospace,monospace';

// Sign goes outside the symbol: -£417.33, not £-417.33. Only "left over" can
// ever be negative.
const fmt = (v) =>
  (v < 0 ? "-" : "") +
  "£" +
  Math.abs(v).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

// Accepts a palette token ("viz-5"), a semantic name ("money-out"), or any raw
// CSS colour. Tokens keep the budget YAML free of hex codes.
const NAMED = {
  "viz-1": VIZ.seq[0], "viz-2": VIZ.seq[1], "viz-3": VIZ.seq[2], "viz-4": VIZ.seq[3],
  "viz-5": VIZ.seq[4], "viz-6": VIZ.seq[5], "viz-7": VIZ.seq[6], "viz-8": VIZ.seq[7],
  "money-out": VIZ.moneyOut, pending: VIZ.pending, accent: VIZ.accent,
};
const resolveColor = (c) => (c == null ? null : NAMED[c] || c);

// Nudges a sorted list of {y} so no two entries sit closer than `min`, kept inside [top, bottom].
function spread(items, min, top, bottom) {
  let prev = top - min;
  items.forEach((it) => {
    it.y = Math.max(it.y, prev + min);
    prev = it.y;
  });
  let next = bottom + min;
  for (let i = items.length - 1; i >= 0; i--) {
    const it = items[i];
    it.y = Math.max(top, Math.min(it.y, next - min));
    next = it.y;
  }
  return items;
}

// Pure layout: returns ribbon paths, node rects, leaf labels and group chips.
// hover is a node id, or null. W/H are the SVG user-space box, not pixels.
function layout(spec, key, W, H, rootColor, hover, showAmounts) {
  const gap = 7;
  const nw = 14;
  const padL = 6;
  const pctX = (v) => ((v / W) * 100).toFixed(3) + "%";
  const pctY = (v) => ((v / H) * 100).toFixed(3) + "%";

  const leaves = [];
  spec.groups.forEach((g, gi) => {
    const color = g.color || SEQ[gi % SEQ.length];
    (g.items || []).forEach((it, ii) =>
      leaves.push({ id: key + "-l" + gi + "-" + ii, g: gi, name: it.name, v: Number(it.amount) || 0, color })
    );
  });
  if (!leaves.length) return null;

  const total = leaves.reduce((s, l) => s + l.v, 0);
  const scale = Math.max(0, H - gap * (leaves.length - 1)) / (total || 1);
  let y = 0;
  leaves.forEach((l) => {
    l.h = Math.max(2.5, l.v * scale);
    l.y = y;
    y += l.h + gap;
  });
  const shift = (H - (y - gap)) / 2;
  leaves.forEach((l) => {
    l.y += shift;
  });

  const x0 = padL;
  const x1 = padL + (W - padL - nw) / 2;
  const x2 = W - nw;

  const groups = spec.groups.map((g, gi) => {
    const own = leaves.filter((l) => l.g === gi);
    const v = own.reduce((s, l) => s + l.v, 0);
    const h = Math.max(2.5, v * scale);
    const last = own[own.length - 1];
    const mid = (own[0].y + last.y + last.h) / 2;
    return {
      id: key + "-g" + gi,
      name: g.name,
      color: g.color || SEQ[gi % SEQ.length],
      v,
      h,
      y: mid - h / 2,
      x: x1,
      w: nw,
    };
  });

  const rootH = groups.reduce((s, m) => s + m.h, 0);
  const root = {
    id: key + "-root",
    name: spec.root,
    color: rootColor,
    v: total,
    h: rootH,
    y: (H - rootH) / 2,
    x: x0,
    w: nw,
  };

  const ribbons = [];
  // Stacks each flow against a running offset on both endpoints, so ribbon
  // order out of a node matches the order its targets were laid out in.
  const flow = (s, t, h, color) => {
    const a = s.outAt === undefined ? (s.outAt = s.y) : s.outAt;
    const b = t.inAt === undefined ? (t.inAt = t.y) : t.inAt;
    s.outAt = a + h;
    t.inAt = b + h;
    const ax = s.x + nw;
    const bx = t.x;
    const mx = (ax + bx) / 2;
    const dim = hover && hover !== s.id && hover !== t.id;
    ribbons.push({
      d:
        "M" + ax + "," + a +
        " C" + mx + "," + a + " " + mx + "," + b + " " + bx + "," + b +
        " L" + bx + "," + (b + h) +
        " C" + mx + "," + (b + h) + " " + mx + "," + (a + h) + " " + ax + "," + (a + h) + " Z",
      color,
      op: hover ? (dim ? 0.12 : 0.72) : 0.42,
    });
  };
  groups.forEach((m) => flow(root, m, m.h, m.color));
  groups.forEach((m, gi) => leaves.filter((l) => l.g === gi).forEach((l) => flow(m, l, l.h, l.color)));

  const nodes = [root]
    .concat(groups, leaves.map((l) => ({ id: l.id, x: x2, y: l.y, w: nw, h: l.h, color: l.color })))
    .map((n) => ({ id: n.id, x: n.x, y: n.y, w: n.w, h: n.h, color: n.color }));

  const labels = spread(leaves.map((l) => ({ y: l.y + l.h / 2, l })), 16, 8, H - 8).map((it) => {
    const l = it.l;
    const rel = !hover || hover === l.id || hover === key + "-g" + l.g;
    return {
      id: l.id,
      top: pctY(it.y),
      name: l.name,
      // Carries the group colour at a fixed size. The leaf's own node rect is
      // as short as 2.5px for small amounts, and spread() pushes labels off
      // their group's vertical band, so without this a label can sit level
      // with a neighbouring group's chip and look like it belongs to it.
      dot: l.color,
      amount: showAmounts ? fmt(l.v) : "",
      tip: spec.groups[l.g].name + " → " + l.name + "  " + fmt(l.v),
      fill: hover ? (rel ? VIZ.textPrimary : VIZ.textMuted) : VIZ.textSecondary,
    };
  });

  const chipH = 25;
  const chips = spread(groups.map((m) => ({ y: m.y + m.h / 2 - chipH / 2, m })), chipH + 4, 0, H - chipH).map(
    (it) => ({
      id: it.m.id,
      left: pctX(it.m.x + nw / 2),
      top: pctY(it.y),
      tf: "translateX(-50%)",
      name: it.m.name,
      amount: fmt(it.m.v),
      stroke: hover === it.m.id ? VIZ.borderStrong : VIZ.borderSubtle,
    })
  );
  chips.unshift({
    id: root.id,
    left: "0%",
    top: "0%",
    tf: "none",
    name: root.name,
    amount: fmt(root.v),
    stroke: hover === root.id ? VIZ.borderStrong : VIZ.borderSubtle,
  });

  return { ribbons, nodes, labels, chips, total };
}

const esc = (s) =>
  String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

class BudgetSankeyCard extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this._hover = null;
  }

  setConfig(config) {
    if (!config || !Array.isArray(config.groups) || !config.groups.length) {
      throw new Error("budget-sankey-card: `groups` must be a non-empty list");
    }
    // Items accept either the compact `- [Mortgage, 1571.39]` pair or the
    // explicit `- {name: …, amount: …}` mapping. The budget YAML is hand-edited
    // through agenix, so the terse form is the one that keeps it readable.
    const groups = config.groups.map((g, i) => {
      if (!g.name) throw new Error("budget-sankey-card: group " + i + " has no name");
      if (!Array.isArray(g.items) || !g.items.length) {
        throw new Error("budget-sankey-card: group '" + g.name + "' has no items");
      }
      const items = g.items.map((it) => {
        const name = Array.isArray(it) ? it[0] : it.name;
        const amount = Number(Array.isArray(it) ? it[1] : it.amount);
        if (!name || !Number.isFinite(amount)) {
          throw new Error(
            "budget-sankey-card: every item in '" + g.name + "' needs a name and a numeric amount"
          );
        }
        return { name, amount };
      });
      return { name: g.name, color: resolveColor(g.color), items };
    });
    if (config.income != null && !Number.isFinite(Number(config.income))) {
      throw new Error("budget-sankey-card: `income` must be a number");
    }
    this._config = Object.assign({}, config, { groups });
    this._hover = null;
    this._render();
  }

  // Static document: nothing to recompute when hass updates.
  set hass(_) {}

  getCardSize() {
    return Math.ceil((this._config?.chart_height || 620) / 50);
  }

  _render() {
    if (!this._config) return;
    const c = this._config;
    const H = c.chart_height || 620;
    const W = 470;
    const accent = resolveColor(c.accent) || VIZ.moneyOut;
    const showAmounts = c.show_amounts !== false;
    const spec = { root: c.root || "Budget", groups: c.groups };
    const l = layout(spec, c.key || "b", W, H, accent, this._hover, showAmounts);
    if (!l) return;

    // With `income` set the header becomes in / out / left; without it, the
    // single total it has always shown. The yearly card omits income, so it is
    // unaffected.
    const income = c.income == null ? null : Number(c.income);
    const stats =
      income == null
        ? [{ label: c.total_label || "TOTAL", value: fmt(l.total), color: accent }]
        : [
            { label: c.income_label || "IN", value: fmt(income), color: VIZ.moneyIn },
            { label: c.total_label || "OUT", value: fmt(l.total), color: accent },
            {
              label: c.left_label || "LEFT",
              value: fmt(income - l.total),
              color: income - l.total >= 0 ? VIZ.moneyIn : VIZ.moneyOut,
            },
          ];

    this.shadowRoot.innerHTML = `
      <style>
        :host { display: block; }
        .card {
          background: ${VIZ.card};
          border: 1px solid ${VIZ.borderSubtle};
          border-top: 2px solid ${accent};
          border-radius: 8px;
          box-shadow: ${VIZ.shadow1};
          padding: 18px 20px 22px;
          color: ${VIZ.textPrimary};
          font: 400 14px/1.55 ${FONT_BODY};
          box-sizing: border-box;
          overflow: hidden;
        }
        .head { display:flex; align-items:flex-end; justify-content:space-between; gap:16px; margin-bottom:16px; }
        .title { margin:0; font:600 20px/1.3 ${FONT_DISPLAY}; letter-spacing:-.01em; }
        .sub { margin:4px 0 0; font:400 12px/1.3 ${FONT_BODY}; color:${VIZ.textMuted}; }
        .stats { display:flex; gap:20px; flex-wrap:wrap; justify-content:flex-end; }
        .totlab { font:500 11px ${FONT_MONO}; letter-spacing:.06em; color:${VIZ.textMuted}; margin-bottom:4px; text-align:right; }
        .tot { font:700 28px ${FONT_MONO}; letter-spacing:-.02em; color:${accent}; font-variant-numeric:tabular-nums; text-align:right; }
        .stats .tot.sm { font-size:22px; }
        .body { display:flex; align-items:stretch; width:100%; }
        .plot { position:relative; flex:1; min-width:0; }
        svg { display:block; }
        path { transition: opacity 140ms cubic-bezier(.2,.8,.2,1); }
        rect { cursor: default; }
        .chip {
          position:absolute; display:flex; align-items:baseline; gap:8px; padding:3px 8px;
          border-radius:5px; background:${VIZ.raised}; box-shadow:${VIZ.shadow1};
          white-space:nowrap; transition:border-color 140ms cubic-bezier(.2,.8,.2,1);
        }
        .chip b { font:500 12px ${FONT_BODY}; color:${VIZ.textPrimary}; }
        .chip i { font:500 11px ${FONT_MONO}; color:${VIZ.textSecondary}; font-style:normal; font-variant-numeric:tabular-nums; }
        .rail { position:relative; width:min(206px,45%); flex:0 0 min(206px,45%); }
        .lab {
          position:absolute; left:10px; right:0; display:flex; align-items:baseline; gap:6px;
          transform:translateY(-50%); font:500 11px ${FONT_BODY};
          transition:color 140ms cubic-bezier(.2,.8,.2,1);
        }
        .lab span { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
        .lab em { flex:0 0 auto; width:7px; height:7px; border-radius:2px; align-self:center; }
        .lab i { font:500 11px ${FONT_MONO}; color:${VIZ.textMuted}; font-style:normal; font-variant-numeric:tabular-nums; flex:0 0 auto; }
        @media (max-width: 600px) { .rail { width:min(140px,42%); flex-basis:min(140px,42%); } }
      </style>
      <div class="card">
        <div class="head">
          <div>
            <h2 class="title">${esc(c.title || "Budget")}</h2>
            ${c.subtitle ? `<p class="sub">${esc(c.subtitle)}</p>` : ""}
          </div>
          <div class="stats">${stats
            .map(
              (s) =>
                `<div><div class="totlab">${esc(s.label)}</div><div class="tot${
                  stats.length > 1 ? " sm" : ""
                }" style="color:${s.color}">${s.value}</div></div>`
            )
            .join("")}</div>
        </div>
        <div class="body">
          <div class="plot">
            <svg viewBox="0 0 ${W} ${H}" width="100%" height="${H}" preserveAspectRatio="none">
              ${l.ribbons.map((r) => `<path d="${r.d}" fill="${r.color}" opacity="${r.op}"></path>`).join("")}
              ${l.nodes
                .map(
                  (n) =>
                    `<rect data-id="${n.id}" x="${n.x}" y="${n.y}" width="${n.w}" height="${n.h}" rx="2" fill="${n.color}"></rect>`
                )
                .join("")}
            </svg>
            ${l.chips
              .map(
                (ch) =>
                  `<div class="chip" data-id="${ch.id}" style="left:${ch.left};top:${ch.top};transform:${ch.tf};border:1px solid ${ch.stroke}"><b>${esc(
                    ch.name
                  )}</b><i>${ch.amount}</i></div>`
              )
              .join("")}
          </div>
          <div class="rail">
            ${l.labels
              .map(
                (lb) =>
                  `<div class="lab" data-id="${lb.id}" title="${esc(lb.tip)}" style="top:${lb.top};color:${lb.fill}"><em style="background:${lb.dot}"></em><span>${esc(
                    lb.name
                  )}</span><i>${lb.amount}</i></div>`
              )
              .join("")}
          </div>
        </div>
      </div>
    `;

    // Re-rendering the whole subtree on hover would kill the CSS transitions,
    // so hover is delegated once and only the affected attributes are patched.
    const root = this.shadowRoot;
    root.querySelectorAll("[data-id]").forEach((el) => {
      el.addEventListener("mouseenter", () => this._setHover(el.dataset.id));
      el.addEventListener("mouseleave", () => this._setHover(null));
    });
  }

  _setHover(id) {
    if (this._hover === id) return;
    this._hover = id;
    const c = this._config;
    const H = c.chart_height || 620;
    const accent = resolveColor(c.accent) || VIZ.moneyOut;
    const l = layout({ root: c.root || "Budget", groups: c.groups }, c.key || "b", 470, H, accent, id, c.show_amounts !== false);
    if (!l) return;
    const root = this.shadowRoot;
    root.querySelectorAll("path").forEach((p, i) => {
      if (l.ribbons[i]) p.setAttribute("opacity", l.ribbons[i].op);
    });
    root.querySelectorAll(".chip").forEach((el, i) => {
      if (l.chips[i]) el.style.borderColor = l.chips[i].stroke;
    });
    root.querySelectorAll(".lab").forEach((el, i) => {
      if (l.labels[i]) el.style.color = l.labels[i].fill;
    });
  }
}

customElements.define("budget-sankey-card", BudgetSankeyCard);

window.customCards = window.customCards || [];
window.customCards.push({
  type: "budget-sankey-card",
  name: "Budget Sankey",
  description: "Three-level sankey of a hand-maintained budget, defined in YAML",
});
