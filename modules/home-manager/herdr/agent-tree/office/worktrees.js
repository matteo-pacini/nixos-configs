// Sorts agents into the office's floor plan: a machine is a building, a repo a
// floor (agents outside any repo go to its Lobby), a git worktree a room. Where
// a pane's folder belongs is asked of git on that pane's machine, cached here
// for the whole app (all office dialogs share it).

import { agents, terminals, spaces, panes, exec } from "herdr";

// Re-ask git about a folder this often: a checkout can appear or go.
const GIT_MS = 5 * 60000;
// `${machine}\0${cwd}` -> { at, top, common, pending } (null top: not in a repo).
const gitInfo = new Map();

// `cwd` on `machine` (null: this one): { top, common } once known, else null,
// and a lookup starts that notifies `cx` when it's done.
function worktree(machine, cwd, cx) {
  const key = `${machine ?? ""}\0${cwd}`;
  const known = gitInfo.get(key);
  if (!known || Date.now() - known.at > GIT_MS) {
    gitInfo.set(key, { ...known, at: Date.now(), pending: !known });
    cx.spawn(async (cx) => {
      const r = await exec("git", ["-C", cwd, "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir"], { on: machine })
        .catch(() => null);
      const [top, common] = r?.code === 0 ? r.stdout.trim().split("\n") : [];
      gitInfo.set(key, { at: Date.now(), top: top ?? null, common: common ?? null });
      cx.notify();
    });
  }
  return known && !known.pending ? known : null;
}

const base = (p) => p.replace(/\/+$/, "").split("/").pop();
// The repo a git common dir belongs to: the folder holding `.git`, or a bare repo's own name.
const repoName = (common) => (common.endsWith("/.git") ? base(common.slice(0, -5)) : base(common).replace(/\.git$/, ""));

/**
 * Every agent, placed. `blockedKid(a)` is the sub-agent of `a` waiting on the
 * person, if any: sub-agents have no cubicle, so their parent asks for them.
 *
 * Returns `{ buildings, all, pending, worktrees }`:
 * - `buildings`: `[machine, floors]` pairs, this computer (null) first, where
 *   `floors` maps a repo name ("" for the Lobby) to its rooms, and rooms map a
 *   worktree path ("" outside git) to `{ top, main, name, agents }`.
 * - `all`: every placed entry, `{ a, kid, labels, machine, room, repo }`, where
 *   `a` is the agent (shown as blocked when `kid` is), `labels` its terminal's.
 * - `pending`: agents left out while git is still being asked about them.
 * - `worktrees`: how many rooms are in a repo.
 */
export function floorPlan(cx, blockedKid) {
  const terms = new Map(terminals().map((k) => [k.address, k]));
  const paneOf = new Map(panes().map((p) => [p.pane, p]));
  const machineOf = new Map(spaces().map((s) => [s.id, s.machine ?? null]));

  const byMachine = new Map();
  let pending = 0;
  for (const a of agents()) {
    const machine = machineOf.get(a.space) ?? (a.address.includes("/") ? a.address.split("/")[0] : null);
    const pane = paneOf.get(a.pane);
    const git = pane?.cwd ? worktree(machine, pane.cwd, cx) : { top: null };
    if (!git) { pending++; continue; }
    const repo = git.top ? repoName(git.common) : "";
    const roomKey = git.top ?? "";
    if (!byMachine.has(machine)) byMachine.set(machine, new Map());
    const floors = byMachine.get(machine);
    if (!floors.has(repo)) floors.set(repo, new Map());
    const rooms = floors.get(repo);
    if (!rooms.has(roomKey)) {
      rooms.set(roomKey, {
        top: git.top,
        main: Boolean(git.top) && `${git.top}/.git` === git.common,
        name: git.top ? (pane?.branch || base(git.top)) : "outside git",
        agents: [],
      });
    }
    const room = rooms.get(roomKey);
    const kid = a.status === "blocked" ? null : blockedKid(a);
    room.agents.push({ a: kid ? { ...a, status: "blocked" } : a, kid, labels: terms.get(a.address)?.labels ?? {}, machine, room, repo });
  }

  const buildings = [...byMachine.entries()].sort(([x], [y]) => (x === null ? -1 : y === null ? 1 : x.localeCompare(y)));
  const roomsOf = (floors) => [...floors.values()].flatMap((rooms) => [...rooms.values()]);
  const all = buildings.flatMap(([, floors]) => roomsOf(floors).flatMap((r) => r.agents));
  const worktrees = buildings.reduce((n, [, floors]) => n + roomsOf(floors).filter((r) => r.top).length, 0);
  return { buildings, all, pending, worktrees };
}
