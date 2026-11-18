import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { mock, calls } from "herdr";
import { find } from "gpui-kit";
import Spaces from "../../mods/space-cards/main.js";

// Every "+" that makes a space, in both sidebar widths, for this computer and
// another machine, whichever machine's space has focus. A per-machine "+" must
// always name its machine: left out, herdr makes the space on the focused
// space's machine. "" is this computer.

const REMOTE = "nexus";

// spaces(): one per machine named in `on` (null = this computer); `focus` is
// the machine of the active one.
const space = (machine, focus) => ({
  id: machine ? `${machine}/1` : "1",
  name: machine ? "remote work" : "local work",
  machine,
  active: machine === focus,
  folder: "/home/u",
  tabs: [],
});

// `width`: the sidebar's, below 160 is the icon rail.
function setup({ on, focus, width = 260, state = "connected", folded = [], remotes = [REMOTE] }) {
  const store = { "machines.folded": JSON.stringify(folded) };
  globalThis.localStorage = { getItem: (k) => store[k] ?? null, setItem: (k, v) => { store[k] = v; } };
  mock({
    spaces: () => on.map((m) => space(m, focus)),
    panes: () => [],
    machines: () => remotes.map((name) => ({ name, layout: state === "connected" ? "ready" : "unavailable" })),
    hc: async () => ({ code: 0, stdout: JSON.stringify({ machines: remotes.map((name) => ({ name, state })) }) }),
    layout: () => ({ id: "root", children: [{ id: "sidebar", size: { px: width } }] }),
    theme: () => new Proxy({}, { get: (_t, k) => `t.${String(k)}` }),
    shared: () => undefined,
    setShared: () => {},
    settings: () => ({}),
    window: () => ({ active: false }),
    run: () => {},
  });
}

// A started view (machines listed) and its cx; spawned tasks run to completion.
async function start() {
  const tasks = [];
  const cx = { timer: { every() {} }, spawn: (fn) => tasks.push(fn(cx)), notify() {}, stop_propagation() {} };
  const view = new Spaces();
  view.init({}, cx);
  await Promise.all(tasks);
  return { view, cx };
}

// What clicking `id` asked herdr for: the space.new runs, as their arguments.
function click(view, cx, id, hover) {
  if (hover) find(view.render(), `machine-${hover}`).on.on_hover(true, cx);
  const el = find(view.render(), id);
  assert.ok(el, `${id} is drawn`);
  calls.length = 0;
  el.on.on_click({}, cx);
  return calls.filter(([name]) => name === "run").map(([, cmd, args]) => [cmd, args]);
}

const drawn = (view, id, hover) => {
  if (hover) find(view.render(), `machine-${hover}`).on.on_hover(true, { notify() {} });
  return find(view.render(), id) !== null;
};

const KEYS = { [null]: "local", [REMOTE]: REMOTE };
const ARGS = { [null]: { machine: "" }, [REMOTE]: { machine: REMOTE } };

beforeEach(() => mock({}));

for (const focus of [null, REMOTE]) {
  const focused = focus ? "a remote space" : "a local space";
  for (const target of [null, REMOTE]) {
    const key = KEYS[target];
    const other = target ? null : REMOTE;

    test(`card "+" for ${key}, ${focused} focused`, async () => {
      setup({ on: [null, REMOTE], focus });
      const { view, cx } = await start();
      assert.deepEqual(click(view, cx, `machine-add-${key}`, key), [["space.new", ARGS[target]]]);
    });

    test(`card "New space there" for an empty ${key}, ${focused} focused`, async () => {
      setup({ on: [other], focus });
      const { view, cx } = await start();
      assert.deepEqual(click(view, cx, `machine-new-${key}`), [["space.new", ARGS[target]]]);
    });

    test(`rail "+" row for an empty ${key}, ${focused} focused`, async () => {
      setup({ on: [other], focus, width: 60 });
      const { view, cx } = await start();
      assert.deepEqual(click(view, cx, `machine-new-${key}`), [["space.new", ARGS[target]]]);
    });
  }

  // The toolbar's "+" belongs to no machine: herdr picks the focused one.
  for (const width of [260, 60]) {
    test(`toolbar "+" at ${width} px names no machine, ${focused} focused`, async () => {
      setup({ on: [null, REMOTE], focus, width });
      const { view, cx } = await start();
      assert.deepEqual(click(view, cx, "space-new"), [["space.new", undefined]]);
    });
  }
}

test("card '+' shows only on hover", async () => {
  setup({ on: [null, REMOTE], focus: null });
  const { view } = await start();
  for (const key of ["local", REMOTE]) {
    assert.equal(drawn(view, `machine-add-${key}`), false, key);
    assert.equal(drawn(view, `machine-add-${key}`, key), true, key);
  }
});

test("the rail's machine headers have no '+'", async () => {
  setup({ on: [null, REMOTE], focus: null, width: 60 });
  const { view } = await start();
  for (const key of ["local", REMOTE]) {
    assert.equal(drawn(view, `machine-${key}`), true, key);
    assert.equal(drawn(view, `machine-add-${key}`), false, key);
  }
});

test("a card for a machine that isn't connected has no '+'", async () => {
  setup({ on: [null, REMOTE], focus: null, state: "asleep" });
  const { view } = await start();
  assert.equal(drawn(view, `machine-add-${REMOTE}`, REMOTE), false);
  assert.equal(drawn(view, "machine-add-local", "local"), true);
});

// Unlike the card's "+", the empty row doesn't check the connection.
test("an empty machine that isn't connected still offers 'New space there', naming it", async () => {
  for (const width of [260, 60]) {
    setup({ on: [null], focus: null, width, state: "asleep" });
    const { view, cx } = await start();
    assert.deepEqual(click(view, cx, `machine-new-${REMOTE}`), [["space.new", { machine: REMOTE }]], `${width} px`);
  }
});

test("a folded machine offers no 'New space there'", async () => {
  for (const width of [260, 60]) {
    setup({ on: [], focus: null, width, folded: [null, REMOTE] });
    const { view } = await start();
    assert.equal(drawn(view, "machine-new-local"), false, `${width} px`);
    assert.equal(drawn(view, `machine-new-${REMOTE}`), false, `${width} px`);
  }
});

test("the rail with no other machine has no machine headers", async () => {
  setup({ on: [null], focus: null, width: 60, remotes: [] });
  const { view } = await start();
  assert.equal(drawn(view, "machine-add-local"), false);
  assert.equal(drawn(view, "machine-local"), false);
});
