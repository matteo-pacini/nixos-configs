// Tests for everything in budget-sankey-card.js outside the date logic, which
// budget-sankey-card.test.js covers: config validation, formatting, the sankey
// layout, and the header, navigation and changelog markup the card renders.
//
// Run with `node --test` from this directory; the Nix build of the card runs
// them too.

const test = require("node:test");
const assert = require("node:assert/strict");
const { ctx, card: c, plain, setToday, make } = require("./budget-sankey-card.harness.js");
const { VIZ, SEQ, fmt, resolveColor, today, fmtDay, spread, layout, esc } = c;

const html = (el) => el.shadowRoot.innerHTML;

// The header's stats as [label, value, colour] rows, in order.
const stats = (el) =>
  [...html(el).matchAll(/<div class="totlab">([^<]*)<\/div><div class="tot[^"]*" style="color:([^"]*)">([^<]*)</g)].map(
    (m) => [m[1], m[3], m[2]]
  );

// The changelog as [text, colour] rows, in order.
const log = (el) => [...html(el).matchAll(/<li style="color:([^"]*)">([^<]*)<\/li>/g)].map((m) => [m[2], m[1]]);

const nav = (el) => {
  const m = /<div class="nav"><button class="prev"[^>]*?( disabled)?>‹<\/button><span>([^<]*)<\/span><button class="next"[^>]*?( disabled)?>›/.exec(
    html(el)
  );
  return m && { label: m[2], prev: !m[1], next: !m[3] };
};

const oneGroup = (items) => ({ groups: [{ name: "G", items }] });

test.beforeEach(() => setToday("2026-09-24"));

// --- registration -----------------------------------------------------------

test("registers the element and its card picker entry", () => {
  assert.equal(ctx.customElements.name, "budget-sankey-card");
  assert.deepEqual(plain(ctx.window.customCards.map((x) => x.type)), ["budget-sankey-card"]);
});

// --- formatting helpers -----------------------------------------------------

test("fmt puts the sign outside the pound sign and always shows pence", () => {
  assert.equal(fmt(0), "£0.00");
  assert.equal(fmt(1234.5), "£1,234.50");
  assert.equal(fmt(2345.678), "£2,345.68");
  assert.equal(fmt(-123.45), "-£123.45");
  assert.equal(fmt(-1234567.8), "-£1,234,567.80");
});

test("fmtDay renders a day in British order", () => {
  assert.equal(fmtDay("2027-07-01"), "1 Jul 2027");
  assert.equal(fmtDay("2026-12-01"), "1 Dec 2026");
});

test("today pads month and day", () => {
  setToday("2027-01-05");
  assert.equal(today(), "2027-01-05");
});

test("resolveColor maps tokens and semantic names and passes raw colours through", () => {
  assert.equal(resolveColor("viz-1"), VIZ.seq[0]);
  assert.equal(resolveColor("viz-8"), VIZ.seq[7]);
  assert.equal(resolveColor("money-out"), VIZ.moneyOut);
  assert.equal(resolveColor("pending"), VIZ.pending);
  assert.equal(resolveColor("accent"), VIZ.accent);
  assert.equal(resolveColor("#123456"), "#123456");
  assert.equal(resolveColor(null), null);
  assert.equal(resolveColor(undefined), null);
});

test("esc escapes markup characters", () => {
  assert.equal(esc('<a href="x">&</a>'), "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;");
  assert.equal(esc(12), "12");
});

// --- config validation ------------------------------------------------------

test("setConfig requires a non-empty groups list", () => {
  for (const cfg of [null, {}, { groups: [] }, { groups: "x" }]) {
    assert.throws(() => make(cfg), /`groups` must be a non-empty list/);
  }
});

test("setConfig requires every group to have a name and items", () => {
  assert.throws(() => make({ groups: [{ name: "A", items: [["x", 1]] }, { items: [["y", 1]] }] }), /group 1 has no name/);
  assert.throws(() => make({ groups: [{ name: "G" }] }), /group 'G' has no items/);
  assert.throws(() => make({ groups: [{ name: "G", items: [] }] }), /group 'G' has no items/);
});

test("setConfig requires every item to have a name and a numeric amount", () => {
  for (const it of [["X"], ["", 1], ["X", "abc"], { name: "X" }, { amount: 1 }, { name: "X", amount: "1,000" }]) {
    assert.throws(() => make(oneGroup([it])), /every item in 'G' needs a name and a numeric amount/);
  }
});

test("setConfig accepts pairs, mappings and numeric strings", () => {
  const el = make(oneGroup([["A", 1.5], { name: "B", amount: "12.50" }]));
  assert.deepEqual(plain(el._config.groups[0].items), [
    { name: "A", amount: 1.5 },
    { name: "B", amount: 12.5 },
  ]);
});

test("setConfig ignores extra elements of the pair form, so pairs are never dated", () => {
  const el = make(oneGroup([["A", 1, "2027-01-01"]]));
  assert.deepEqual(plain(el._config.groups[0].items), [{ name: "A", amount: 1 }]);
  assert.deepEqual(plain(el._changes), []);
});

test("setConfig accepts a Date, as the YAML editor produces for an unquoted date", () => {
  const el = make(oneGroup([{ name: "A", amount: 1, until: new ctx.Date("2027-06-30T00:00:00Z") }]));
  assert.equal(el._config.groups[0].items[0].until, "2027-06-30");
});

test("setConfig validates income and incomes", () => {
  const g = oneGroup([["A", 1]]).groups;
  assert.throws(() => make({ groups: g, income: "lots" }), /`income` must be a number/);
  assert.throws(() => make({ groups: g, income: 1, incomes: [["A", 1]] }), /set `income` or `incomes`, not both/);
  assert.throws(() => make({ groups: g, incomes: [] }), /`incomes` must be a non-empty list/);
  assert.throws(() => make({ groups: g, incomes: "A" }), /`incomes` must be a non-empty list/);
  assert.throws(() => make({ groups: g, incomes: [["A"]] }), /every entry in `incomes` needs a name and a numeric amount/);
  assert.doesNotThrow(() => make({ groups: g, income: "2500" }));
});

test("setConfig resolves group colours, defaulting by position", () => {
  const el = make({
    groups: [
      { name: "A", color: "viz-2", items: [["a", 1]] },
      { name: "B", items: [["b", 1]] },
      { name: "C", color: "#abcdef", items: [["c", 1]] },
    ],
  });
  assert.deepEqual(plain(el._config.groups.map((g) => g.color)), [VIZ.seq[1], SEQ[1], "#abcdef"]);
});

test("setConfig resets the selected day and hover", () => {
  const el = make(oneGroup([["A", 1], { name: "B", amount: 1, from: "2027-01-01" }]));
  el._step(1);
  el._hover = "b-root";
  el.setConfig(oneGroup([["A", 1], { name: "B", amount: 1, from: "2027-01-01" }]));
  assert.equal(el._day, null);
  assert.equal(el._hover, null);
});

// --- spread -----------------------------------------------------------------

test("spread pushes neighbours apart to the minimum distance", () => {
  assert.deepEqual(plain(spread([{ y: 0 }, { y: 5 }, { y: 10 }], 10, 0, 100).map((i) => i.y)), [0, 10, 20]);
});

test("spread keeps items inside the bounds", () => {
  assert.deepEqual(plain(spread([{ y: 95 }, { y: 99 }], 10, 0, 100).map((i) => i.y)), [90, 100]);
  assert.deepEqual(plain(spread([{ y: -20 }], 10, 0, 100).map((i) => i.y)), [0]);
});

test("spread leaves items that are already far enough apart alone", () => {
  assert.deepEqual(plain(spread([{ y: 10 }, { y: 50 }], 10, 0, 100).map((i) => i.y)), [10, 50]);
});

test("spread takes a per-pair distance function", () => {
  const items = [{ y: 0, d: 5 }, { y: 1, d: 20 }, { y: 2, d: 5 }];
  const out = spread(items, (a, b) => a.d + b.d, 0, 100).map((i) => i.y);
  assert.deepEqual(plain(out), [0, 25, 50]);
});

// --- layout -----------------------------------------------------------------

const spec = () => ({
  root: "Budget",
  groups: [
    { name: "A", color: "#a", items: [{ name: "a1", amount: 100 }, { name: "a2", amount: 50 }] },
    { name: "B", color: "#b", items: [{ name: "b1", amount: 50 }] },
  ],
});

test("layout returns null when there is nothing to draw", () => {
  assert.equal(layout({ root: "R", groups: [] }, "k", 470, 200, "#f00", null, true), null);
  assert.equal(layout({ root: "R", groups: [{ name: "G", items: [] }] }, "k", 470, 200, "#f00", null, true), null);
});

test("layout draws one node per root, group and leaf, and one ribbon per flow", () => {
  const l = layout(spec(), "k", 470, 200, "#f00", null, true);
  assert.equal(l.total, 200);
  assert.equal(l.nodes.length, 1 + 2 + 3);
  assert.equal(l.ribbons.length, 2 + 3);
  assert.deepEqual(plain(l.labels.map((x) => x.name)), ["a1", "a2", "b1"]);
});

test("layout scales bars by amount and separates groups more than leaves", () => {
  // Scale is 1px per pound; 14px between leaves of a group, 30px between groups.
  const l = layout(spec(), "k", 470, 200, "#f00", null, true);
  assert.equal(l.height, 100 + 14 + 50 + 30 + 50);
  const leaves = l.nodes.slice(3);
  assert.deepEqual(plain(leaves.map((n) => [n.y, n.h])), [
    [0, 100],
    [114, 50],
    [194, 50],
  ]);
  const root = l.nodes[0];
  assert.equal(root.h, 200);
  assert.equal(root.y, (l.height - 200) / 2);
});

test("layout gives a zero amount the minimum bar height", () => {
  const l = layout({ root: "R", groups: [{ name: "G", items: [{ name: "z", amount: 0 }, { name: "x", amount: 10 }] }] }, "k", 470, 10, "#f00", null, true);
  assert.equal(l.nodes[2].h, 3);
});

test("layout widens the gap around a wrapped label", () => {
  const tiny = {
    root: "R",
    groups: [
      { name: "A", items: [{ name: "a1", amount: 1 }, { name: "a2", amount: 1 }] },
      { name: "B", items: [{ name: "b1", amount: 1 }] },
    ],
  };
  assert.equal(layout(tiny, "k", 470, 3, "#f00", null, true).height, 3 + 14 + 3 + 30 + 3);
  assert.equal(layout(tiny, "k", 470, 3, "#f00", null, true, [30, 14, 14]).height, 3 + 21 + 3 + 30 + 3);
});

test("layout falls back to the palette for a group without a colour", () => {
  const l = layout({ root: "R", groups: [{ name: "G", items: [{ name: "x", amount: 1 }] }] }, "k", 470, 10, "#f00", null, true);
  assert.equal(l.nodes[1].color, SEQ[0]);
});

test("layout puts the root chip first, then one chip per group", () => {
  const l = layout(spec(), "k", 470, 200, "#f00", null, true);
  assert.deepEqual(plain(l.chips.map((ch) => [ch.name, ch.amount])), [
    ["Budget", "£200.00"],
    ["A", "£150.00"],
    ["B", "£50.00"],
  ]);
  assert.equal(l.chips[0].left, "0%");
});

test("layout labels carry the amount, group dot and a tooltip", () => {
  const l = layout(spec(), "k", 470, 200, "#f00", null, true);
  assert.deepEqual(plain(l.labels[0]), {
    id: "k-l0-0",
    top: l.labels[0].top,
    name: "a1",
    dot: "#a",
    amount: "£100.00",
    tip: "A → a1  £100.00",
    fill: VIZ.textSecondary,
  });
  assert.equal(layout(spec(), "k", 470, 200, "#f00", null, false).labels[0].amount, "");
});

test("layout dims ribbons and labels unrelated to the hovered node", () => {
  assert.deepEqual(plain(layout(spec(), "k", 470, 200, "#f00", null, true).ribbons.map((r) => r.op)), [
    0.42, 0.42, 0.42, 0.42, 0.42,
  ]);
  // Ribbons run root→A, root→B, A→a1, A→a2, B→b1.
  const g = layout(spec(), "k", 470, 200, "#f00", "k-g0", true);
  assert.deepEqual(plain(g.ribbons.map((r) => r.op)), [0.72, 0.12, 0.72, 0.72, 0.12]);
  assert.deepEqual(plain(g.labels.map((x) => x.fill)), [VIZ.textPrimary, VIZ.textPrimary, VIZ.textMuted]);
  assert.equal(g.chips[1].stroke, VIZ.borderStrong);
  assert.equal(g.chips[2].stroke, VIZ.borderSubtle);
  const leaf = layout(spec(), "k", 470, 200, "#f00", "k-l1-0", true);
  assert.deepEqual(plain(leaf.labels.map((x) => x.fill)), [VIZ.textMuted, VIZ.textMuted, VIZ.textPrimary]);
});

// --- rendered header --------------------------------------------------------

const earners = () => ({
  groups: [{ name: "House", items: [["Mortgage", 1500]] }],
  incomes: [
    ["Alex", 3000],
    ["Sam", 1000],
  ],
});

test("incomes render one row per earner, then combined, out and left", () => {
  assert.deepEqual(stats(make(earners())), [
    ["ALEX", "£3,000.00", VIZ.textSecondary],
    ["SAM", "£1,000.00", VIZ.textSecondary],
    ["COMBINED INCOME", "£4,000.00", VIZ.moneyIn],
    ["OUT", "£1,500.00", VIZ.moneyOut],
    ["LEFT", "£2,500.00", VIZ.moneyIn],
  ]);
});

test("a single income renders in, out and left", () => {
  assert.deepEqual(stats(make({ groups: earners().groups, income: 2000 })), [
    ["IN", "£2,000.00", VIZ.moneyIn],
    ["OUT", "£1,500.00", VIZ.moneyOut],
    ["LEFT", "£500.00", VIZ.moneyIn],
  ]);
});

test("a shortfall renders negative and in red", () => {
  assert.deepEqual(stats(make({ groups: earners().groups, income: 1000 }))[2], ["LEFT", "-£500.00", VIZ.moneyOut]);
});

test("labels and accent are configurable", () => {
  const el = make(
    Object.assign(earners(), { income_label: "HOUSEHOLD", total_label: "MONTHLY OUT", left_label: "SPARE", accent: "pending" })
  );
  assert.deepEqual(stats(el).slice(2), [
    ["HOUSEHOLD", "£4,000.00", VIZ.moneyIn],
    ["MONTHLY OUT", "£1,500.00", VIZ.pending],
    ["SPARE", "£2,500.00", VIZ.moneyIn],
  ]);
});

test("a card without income shows its total and the monthly saving", () => {
  const cfg = { groups: [{ name: "Mar", items: [["Service", 300]] }, { name: "Sep", items: [["MOT", 60]] }] };
  assert.deepEqual(stats(make(cfg)), [
    ["TOTAL", "£360.00", VIZ.moneyOut],
    ["SAVE / MONTH", "£30.00", VIZ.accent],
  ]);
  assert.deepEqual(stats(make(Object.assign({}, cfg, { saving_label: "PUT ASIDE" })))[1][0], "PUT ASIDE");
  assert.deepEqual(stats(make(Object.assign({}, cfg, { monthly_saving: false }))), [["TOTAL", "£360.00", VIZ.moneyOut]]);
});

test("a lone stat renders large, several render small", () => {
  assert.match(html(make(Object.assign(oneGroup([["A", 1]]), { monthly_saving: false }))), /class="tot" /);
  assert.doesNotMatch(html(make(Object.assign(oneGroup([["A", 1]]), { monthly_saving: false }))), /class="tot sm"/);
  assert.match(html(make(oneGroup([["A", 1]]))), /class="tot sm"/);
});

test("title, subtitle and root are rendered and escaped", () => {
  const plainCard = html(make(oneGroup([["A", 1]])));
  assert.match(plainCard, /<h2 class="title">Budget<\/h2>/);
  assert.doesNotMatch(plainCard, /class="sub"/);
  const el = html(make(Object.assign(oneGroup([["<A>", 1]]), { title: "Tom & Jerry", subtitle: "<b>", root: "Pot" })));
  assert.match(el, /<h2 class="title">Tom &amp; Jerry<\/h2>/);
  assert.match(el, /<p class="sub">&lt;b&gt;<\/p>/);
  assert.match(el, /<b>Pot<\/b>/);
  assert.match(el, /<span>&lt;A&gt;<\/span>/);
});

test("show_amounts: false hides the leaf amounts but not the chip totals", () => {
  const el = html(make(Object.assign(oneGroup([["A", 12]]), { show_amounts: false })));
  assert.match(el, /<span>A<\/span><i><\/i>/);
  assert.match(el, /<b>G<\/b><i>£12.00<\/i>/);
});

test("getCardSize follows chart_height", () => {
  assert.equal(make(oneGroup([["A", 1]])).getCardSize(), 13);
  assert.equal(make(Object.assign(oneGroup([["A", 1]]), { chart_height: 1000 })).getCardSize(), 20);
});

test("hover without a rendered DOM only records the hovered node", () => {
  const el = make(oneGroup([["A", 1]]));
  el._setHover("b-g0");
  assert.equal(el._hover, "b-g0");
  el._setHover(null);
  assert.equal(el._hover, null);
});

// --- navigation and changelog markup ----------------------------------------

const dated = () => ({
  groups: [
    { name: "House", items: [["Mortgage", 1500]] },
    { name: "Credit cards", items: [{ name: "Plan", amount: 170, until: "2027-06-30" }] },
  ],
  incomes: [
    ["Alex", 3000],
    { name: "Sam", amount: 400, until: "2026-11-30" },
    { name: "Sam", amount: 1000, from: "2026-12-01" },
  ],
});

test("no navigation without a future change", () => {
  assert.equal(nav(make(earners())), null);
  assert.equal(nav(make(oneGroup([["A", 1], { name: "Old", amount: 1, until: "2026-01-01" }]))), null);
});

test("navigation starts on today with only the next arrow enabled, and no changelog", () => {
  const el = make(dated());
  assert.deepEqual(nav(el), { label: "Today", prev: false, next: true });
  assert.deepEqual(log(el), []);
});

test("each future stop renders its date, changelog and figures", () => {
  const el = make(dated());
  el._step(1);
  assert.deepEqual(nav(el), { label: "1 Dec 2026", prev: true, next: true });
  assert.deepEqual(log(el), [["Income Sam £400.00 → £1,000.00", VIZ.moneyIn]]);
  assert.deepEqual(stats(el), [
    ["ALEX", "£3,000.00", VIZ.textSecondary],
    ["SAM", "£1,000.00", VIZ.textSecondary],
    ["COMBINED INCOME", "£4,000.00", VIZ.moneyIn],
    ["OUT", "£1,670.00", VIZ.moneyOut],
    ["LEFT", "£2,330.00", VIZ.moneyIn],
  ]);

  el._step(1);
  assert.deepEqual(nav(el), { label: "1 Jul 2027", prev: true, next: false });
  assert.deepEqual(log(el), [["Removed Credit cards → Plan £170.00", VIZ.moneyIn]]);
  assert.deepEqual(stats(el).slice(3), [
    ["OUT", "£1,500.00", VIZ.moneyOut],
    ["LEFT", "£2,500.00", VIZ.moneyIn],
  ]);
  assert.doesNotMatch(html(el), /<b>Credit cards<\/b>/);
});

test("today's figures leave out entries that have not started yet", () => {
  assert.deepEqual(stats(make(dated())).slice(0, 3), [
    ["ALEX", "£3,000.00", VIZ.textSecondary],
    ["SAM", "£400.00", VIZ.textSecondary],
    ["COMBINED INCOME", "£3,400.00", VIZ.moneyIn],
  ]);
});

test("a stop where every income has ended shows a combined income of zero", () => {
  const el = make({ groups: [{ name: "G", items: [["A", 100]] }], incomes: [{ name: "Job", amount: 500, until: "2026-12-31" }] });
  el._step(1);
  assert.deepEqual(stats(el), [
    ["COMBINED INCOME", "£0.00", VIZ.moneyIn],
    ["OUT", "£100.00", VIZ.moneyOut],
    ["LEFT", "-£100.00", VIZ.moneyOut],
  ]);
  assert.deepEqual(log(el), [["Removed income Job £500.00", VIZ.moneyOut]]);
});

test("changelog text is escaped", () => {
  const el = make(oneGroup([["A", 1], { name: "<X>", amount: 1, from: "2027-01-01" }]));
  el._step(1);
  assert.deepEqual(log(el), [["Added G → &lt;X&gt; £1.00", VIZ.moneyOut]]);
});
