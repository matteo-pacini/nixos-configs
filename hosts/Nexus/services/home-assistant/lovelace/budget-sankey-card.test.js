// Tests for the date handling in budget-sankey-card.js: which entries apply on
// a day, the stops the navigation visits, and the changelog between stops.
//
// Run with `node --test` from this directory; the Nix build of the card runs
// them too.

const test = require("node:test");
const assert = require("node:assert/strict");
const { ctx, card: c, plain, setToday, make: card } = require("./budget-sankey-card.harness.js");
const { toDay, dayAfter, changelog } = c;

// A monthly budget with a plan that ends, a pay change for one
// earner, and an item that starts later.
const monthly = () => ({
  incomes: [
    ["Alex", 4000],
    { name: "Sam", amount: 400, until: "2026-11-30" },
    { name: "Sam", amount: 1000, from: "2026-12-01" },
  ],
  groups: [
    { name: "House", items: [["Mortgage", 1500]] },
    { name: "Credit cards", items: [{ name: "Loan", amount: 170, until: "2027-06-30" }] },
    { name: "Bills", items: [["Council Tax", 200], { name: "Gym", amount: 40, from: "2027-01-01" }] },
  ],
});

const names = (el) => plain(el._spec().groups.map((g) => [g.name, g.items.map((it) => it.name)]));

test.beforeEach(() => setToday("2026-09-24"));

test("toDay reduces strings, Dates and timestamps to a day", () => {
  assert.equal(toDay("2027-06-30"), "2027-06-30");
  assert.equal(toDay("2027-06-30T00:00:00.000Z"), "2027-06-30");
  assert.equal(toDay(new ctx.Date("2027-06-30T00:00:00Z")), "2027-06-30");
  assert.equal(toDay("19/05/2027"), null);
});

test("dayAfter crosses month, year and leap day", () => {
  assert.equal(dayAfter("2027-06-30"), "2027-07-01");
  assert.equal(dayAfter("2026-11-30"), "2026-12-01");
  assert.equal(dayAfter("2026-12-31"), "2027-01-01");
  assert.equal(dayAfter("2028-02-28"), "2028-02-29");
});

test("setConfig rejects a malformed date", () => {
  assert.throws(
    () => card({ groups: [{ name: "G", items: [{ name: "X", amount: 1, until: "May 2027" }] }] }),
    /'X' `until` must be a YYYY-MM-DD date/
  );
  assert.throws(
    () => card({ incomes: [{ name: "A", amount: 1, from: "soon" }], groups: [{ name: "G", items: [["X", 1]] }] }),
    /'A' `from` must be a YYYY-MM-DD date/
  );
});

test("change points come from items and incomes, until counting as the day after", () => {
  assert.deepEqual(plain(card(monthly())._changes), ["2026-12-01", "2027-01-01", "2027-07-01"]);
});

test("stops start today and skip change points already past", () => {
  const el = card(monthly());
  assert.deepEqual(plain(el._stops()), ["2026-09-24", "2026-12-01", "2027-01-01", "2027-07-01"]);
  setToday("2027-02-10");
  assert.deepEqual(plain(el._stops()), ["2027-02-10", "2027-07-01"]);
});

test("a card without future changes has only today", () => {
  const el = card({ groups: [{ name: "G", items: [["X", 1], { name: "Old", amount: 1, until: "2026-01-01" }] }] });
  assert.deepEqual(plain(el._stops()), ["2026-09-24"]);
  assert.deepEqual(names(el), [["G", ["X"]]]);
});

test("until and from are inclusive, and an emptied group is dropped", () => {
  const el = card(monthly());
  el._day = "2027-06-30";
  assert.deepEqual(names(el), [
    ["House", ["Mortgage"]],
    ["Credit cards", ["Loan"]],
    ["Bills", ["Council Tax", "Gym"]],
  ]);
  el._day = "2027-07-01";
  assert.deepEqual(names(el), [
    ["House", ["Mortgage"]],
    ["Bills", ["Council Tax", "Gym"]],
  ]);
  el._day = "2026-12-31";
  assert.deepEqual(names(el)[2], ["Bills", ["Council Tax"]]);
});

test("a group keeps its default colour when an earlier group is dated out", () => {
  const el = card(monthly());
  const before = el._spec().groups.find((g) => g.name === "Bills").color;
  el._day = "2027-07-01";
  assert.equal(el._spec().groups.find((g) => g.name === "Bills").color, before);
});

test("stepping walks the stops and returns to following today", () => {
  const el = card(monthly());
  el._step(-1);
  assert.equal(el._day, null);
  el._step(1);
  assert.equal(el._day, "2026-12-01");
  el._step(1);
  el._step(1);
  assert.equal(el._day, "2027-07-01");
  el._step(1);
  assert.equal(el._day, "2027-07-01");
  el._step(-1);
  el._step(-1);
  el._step(-1);
  assert.equal(el._day, null);
});

test("a selected day that has become today or past is dropped on render", () => {
  const el = card(monthly());
  el._step(1);
  setToday("2026-12-01");
  el._render();
  assert.equal(el._day, null);
});

test("changelog reports a dated pair of incomes as one change", () => {
  const el = card(monthly());
  assert.deepEqual(plain(changelog(el._config, "2026-09-24", "2026-12-01")), [
    { text: "Income Sam £400.00 → £1,000.00", good: true },
  ]);
});

test("changelog reports added and removed expenses", () => {
  const el = card(monthly());
  assert.deepEqual(plain(changelog(el._config, "2026-12-01", "2027-01-01")), [
    { text: "Added Bills → Gym £40.00", good: false },
  ]);
  assert.deepEqual(plain(changelog(el._config, "2027-01-01", "2027-07-01")), [
    { text: "Removed Credit cards → Loan £170.00", good: true },
  ]);
});

test("changelog reports an income drop and an expense rise as bad", () => {
  const el = card({
    incomes: [
      { name: "A", amount: 2000, until: "2026-12-31" },
      { name: "A", amount: 1500, from: "2027-01-01" },
    ],
    groups: [
      {
        name: "Bills",
        items: [
          { name: "Energy", amount: 100, until: "2026-12-31" },
          { name: "Energy", amount: 150, from: "2027-01-01" },
        ],
      },
    ],
  });
  assert.deepEqual(plain(changelog(el._config, "2026-12-31", "2027-01-01")), [
    { text: "Income A £2,000.00 → £1,500.00", good: false },
    { text: "Bills → Energy £100.00 → £150.00", good: false },
  ]);
});

test("changelog leaves out an entry whose amount is unchanged", () => {
  const el = card({
    groups: [
      {
        name: "G",
        items: [
          { name: "Same", amount: 10, until: "2026-12-31" },
          { name: "Same", amount: 10, from: "2027-01-01" },
        ],
      },
    ],
  });
  assert.deepEqual(plain(changelog(el._config, "2026-12-31", "2027-01-01")), []);
});
