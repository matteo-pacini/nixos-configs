// The fleet panel's decisions: the state held from desk-fleet's events, and
// what the panel and the bar draw from it. The helper decides every chip,
// line text and allowed action; this file only orders, folds and words what
// it sent, and turns keys into commands. Plain JavaScript so node can run it
// too. Times are milliseconds since the epoch.

// The actions that run in the helper's background session per host.
const SESSION_ACTIONS = ["switch", "boot", "mode", "reboot"];

// Mode chooser numbers, fixed so a macOS host shows 1 and 3.
const MODES = [
    { n: 1, value: "manual", label: "manual" },
    { n: 2, value: "boot", label: "automatic boot" },
    { n: 3, value: "switch", label: "automatic switch" }
];

// The state before the helper has said anything. `helper` is "running",
// "starting", "stopped" (it exited) or "missing" (it could not start).
function initial(helper) {
    return {
        helper: helper,
        hello: null,
        rows: {},
        github: null,
        round: null,
        lastDone: null,
        // Host -> { id, action, state, tail, exit, reason }: its last session
        // action this run.
        actions: {},
        // Host -> the helper's message text while its action runs.
        messages: {},
        // Command id -> { cmd, host }, until its final action event.
        commands: {}
    };
}

function copy(st, changes) {
    return Object.assign({}, st, changes);
}

function withEntry(map, key, value) {
    const out = Object.assign({}, map);
    out[key] = value;
    return out;
}

function without(map, key) {
    const out = Object.assign({}, map);
    delete out[key];
    return out;
}

function parseTime(t) {
    if (typeof t !== "string" || t === "")
        return null;
    const ms = Date.parse(t);
    return isNaN(ms) ? null : ms;
}

function short(sha) {
    return typeof sha === "string" ? sha.slice(0, 7) : "";
}

// Records a command written to the helper.
function sent(st, id, cmd) {
    return copy(st, { commands: withEntry(st.commands, id, { cmd: cmd.cmd, host: cmd.host || null }) });
}

// The state after one event from the helper.
function apply(st, ev) {
    switch (ev.event) {
    case "hello":
        return copy(st, { hello: ev });
    case "round":
        return copy(st, { round: ev, lastDone: ev.state === "done" ? parseTime(ev.at) : st.lastDone });
    case "host":
        return copy(st, { rows: withEntry(st.rows, ev.host, ev) });
    case "github":
        return copy(st, { github: ev });
    case "message":
        return copy(st, { messages: withEntry(st.messages, ev.host, ev.text) });
    case "action": {
        const out = copy(st, {});
        if (ev.id !== null && ev.id !== undefined && ["ok", "failed", "refused"].includes(ev.state))
            out.commands = without(st.commands, ev.id);
        if (!ev.host || !SESSION_ACTIONS.includes(ev.action) || ev.state === "refused")
            return out;
        const before = st.actions[ev.host];
        const same = before && before.id === (ev.id ?? null) && before.action === ev.action;
        out.actions = withEntry(st.actions, ev.host, {
            id: ev.id ?? null,
            action: ev.action,
            state: ev.state,
            tail: ev.tail || (same && ev.state !== "started" ? before.tail : []),
            exit: typeof ev.exit === "number" ? ev.exit : null,
            reason: ev.reason || ""
        });
        if (ev.state === "started" || ev.state === "ok" || ev.state === "failed")
            out.messages = without(st.messages, ev.host);
        return out;
    }
    }
    return st;
}

// The single plain line shown instead of the whole panel, or "".
function single(st) {
    if (st.helper === "missing")
        return "The fleet helper (desk-fleet) was not found.";
    if (st.helper === "stopped")
        return "The fleet helper (desk-fleet) stopped. Trying again.";
    return "";
}

// Host names to draw, in the hello's order with online hosts first; only
// hosts that have a row.
function order(st) {
    const names = st.hello ? st.hello.hosts.map(h => h.host) : [];
    const have = names.filter(n => st.rows[n]);
    return have.filter(n => st.rows[n].online).concat(have.filter(n => !st.rows[n].online));
}

// "Checking A · B…" for hosts with no row yet, or "".
function checking(st) {
    if (!st.hello)
        return st.helper === "running" || st.helper === "starting" ? "Starting…" : "";
    const left = st.hello.hosts.map(h => h.host).filter(n => !st.rows[n]);
    return left.length ? `Checking ${left.join(" · ")}…` : "";
}

// The header's right side: "checking…" while a round runs, else "checked
// 20s ago", or "" before anything.
function checked(st, now) {
    if (st.round && st.round.state === "started")
        return "checking…";
    if (st.lastDone === null)
        return st.hello ? "checking…" : "";
    const s = Math.max(0, Math.round((now - st.lastDone) / 1000));
    const ago = s < 60 ? `${s}s` : s < 3600 ? `${Math.floor(s / 60)}m` : `${Math.floor(s / 3600)}h`;
    return `checked ${ago} ago`;
}

// "read only" or "live" once the helper said which, else "".
function liveText(st) {
    if (!st.hello)
        return "";
    return st.hello.read_only ? "read only" : "live";
}

// The pipeline line: null before GitHub answered; { error } on an error;
// else { parts: [{ label, text, tone }] }, tone "" | "green" | "red" |
// "cyan" | "orange".
function pipeline(st) {
    const g = st.github;
    if (!g)
        return null;
    if (g.state !== "ok")
        return { error: `GitHub: ${g.error}. Hosts are still read; Behind cannot be judged.` };
    const parts = [{ label: "master", text: short(g.master) || "—", tone: "" }];
    const r = g.run;
    if (r) {
        let text, tone;
        if (r.status !== "completed") {
            text = r.status === "queued" || r.status === "waiting" || r.status === "pending" ? "queued" : "building";
            tone = "cyan";
        } else if (r.conclusion === "success") {
            text = "passed";
            tone = "green";
        } else {
            text = r.conclusion || "failed";
            tone = r.conclusion === "cancelled" || r.conclusion === "skipped" ? "orange" : "red";
        }
        if (r.head_sha && g.master && r.head_sha !== g.master)
            text += ` (${short(r.head_sha)})`;
        parts.push({ label: "build", text, tone });
    } else {
        parts.push({ label: "build", text: "no run", tone: "" });
    }
    const ahead = typeof g.ahead === "number" && g.ahead > 0 ? ` · ${g.ahead} behind` : "";
    parts.push({ label: "deploy", text: (short(g.deploy) || "—") + ahead, tone: ahead ? "orange" : "" });
    return { parts };
}

// The device glyphs the design draws.
function glyph(device) {
    return device === "server" ? "▤" : device === "laptop" ? "▭" : "▣";
}

function modePill(mode) {
    if (mode === "manual")
        return { text: "manual", auto: false };
    if (mode === "boot" || mode === "switch")
        return { text: `auto ${mode}`, auto: true };
    return null;
}

// The info object as { label, value } lines: nested keys joined with a
// space, one line per list item, empty objects and lists left out.
function infoLines(info) {
    const out = [];
    const walk = (label, v) => {
        if (v === null || v === undefined)
            out.push({ label, value: "—" });
        else if (Array.isArray(v))
            v.forEach(x => walk(label, x));
        else if (typeof v === "object")
            Object.keys(v).forEach(k => walk(label ? `${label} ${k}` : k, v[k]));
        else
            out.push({ label, value: String(v) });
    };
    if (info && typeof info === "object")
        walk("", info);
    return out;
}

// The last session action as a row line, or null.
function actionLine(action) {
    if (!action)
        return null;
    const last = action.tail.length ? action.tail[action.tail.length - 1] : "";
    if (action.state === "started" || action.state === "running")
        return { text: `${action.action}: running` + (last ? ` · ${last}` : ""), tone: "", busy: true };
    if (action.state === "ok")
        return { text: `${action.action}: ok`, tone: "green", busy: false };
    const why = action.exit !== null ? `failed (exit ${action.exit})` : "failed" + (action.reason ? ` · ${action.reason}` : "");
    return { text: `${action.action}: ${why}` + (last ? ` · ${last}` : ""), tone: "red", busy: false };
}

// Whether I has anything to unfold.
function hasMore(row) {
    return !!row.info || row.lines.some(l => l.text !== l.first);
}

// The keys drawn under the selected row: [{ key, label, hl, danger }], only
// the ones that work.
function keys(row, action) {
    const a = row.actions || {};
    const out = [];
    const ok = name => a[name] && a[name].allowed;
    if (ok("switch"))
        out.push({ key: "S", label: "switch", hl: true });
    if (ok("boot"))
        out.push({ key: "B", label: "next boot" });
    if (ok("diff"))
        out.push({ key: "D", label: "diff" });
    if (ok("mode"))
        out.push({ key: "M", label: "mode" });
    if (ok("reboot"))
        out.push({ key: "R", label: "reboot" });
    if (ok("ssh"))
        out.push({ key: "T", label: row.local ? "terminal" : "ssh" });
    if (hasMore(row))
        out.push({ key: "I", label: "info" });
    if (action)
        out.push({ key: "A", label: "output" });
    return out;
}

// The row as drawn. `unfolded`: I was pressed on it.
function rowView(row, unfolded, action, message) {
    const runs = row.runs;
    const lines = [];
    if (runs)
        lines.push({ label: "runs", text: runs.text, tone: runs.source === "hand" ? "yellow" : runs.source === "testing" ? "pink" : "" });
    for (const l of row.lines) {
        const folded = !unfolded && l.text !== l.first;
        lines.push({ label: l.key, text: folded ? `${l.first} … (I for all)` : l.text, tone: l.tone || "" });
    }
    const act = actionLine(action);
    return {
        host: row.host,
        glyph: glyph(row.device),
        local: !!row.local,
        dim: !row.online,
        mode: modePill(row.mode),
        chip: { label: row.chip.label, colour: row.chip.colour, busy: row.chip.id === "deploying" || row.chip.id === "building" },
        lines,
        action: act,
        // The helper's message about the running action, under it.
        message: message || "",
        info: unfolded ? infoLines(row.info) : []
    };
}

// The commit a row line starts with ("073c52e · …"), or "".
function lineCommit(row, key) {
    const l = row.lines.find(x => x.key === key);
    const m = l ? /^([0-9a-f]{7})( ·|$)/.exec(l.text) : null;
    return m ? m[1] : "";
}

// The question asked in the row before switch, reboot or mode:
// { title, text, keys: [{ key, label, hl, danger }], choices? }.
function question(row, what) {
    const a = row.actions;
    const runs = row.runs || {};
    if (what === "switch") {
        const target = a.switch.target;
        const commit = lineCommit(row, target === "held" ? "held" : target === "staged" ? "boot" : "failed");
        const title = target === "retry" ? `Retry the deploy${commit ? ` of ${commit}` : ""} on ${row.host} now?` : `Switch ${row.host}${commit ? ` to ${commit}` : ""} now?`;
        const text = [];
        if (runs.source === "hand")
            text.push("It replaces a system built by hand.");
        else if (runs.source === "testing")
            text.push(`It replaces ${short(runs.commit)} from ${runs.branch}.`);
        const held = target === "held" ? row.lines.find(x => x.key === "held") : null;
        if (held && held.same_as_running)
            text.push("Nothing that runs changes; comin records it as deployed.");
        else if (held && held.testing)
            text.push("comin runs a testing generation with test: live until the next reboot, never the next boot.");
        else if (row.darwin)
            text.push("Changed services restart.");
        else
            text.push("Changed services restart, and it becomes the next boot.");
        const k = [{ key: "Enter", label: "switch", hl: true }];
        if (a.diff && a.diff.allowed)
            k.push({ key: "D", label: "diff first" });
        k.push({ key: "Esc", label: "cancel" });
        return { title, text: text.join(" "), keys: k };
    }
    if (what === "reboot") {
        const commit = lineCommit(row, "boot");
        const text = [];
        if (commit)
            text.push(`It comes back on ${commit}${runs.source === "testing" ? " and leaves the testing branch" : ""}.`);
        else if (runs.source === "testing")
            text.push("It leaves the testing branch.");
        else if (row.lines.some(x => x.key === "boot" && x.text === "unknown"))
            text.push("Which system it boots is not known (I says why).");
        text.push(row.local ? "This computer restarts at once." : "If sudo asks for a password, a terminal opens for it.");
        return {
            title: row.local ? "Reboot this computer now?" : `Reboot ${row.host} now?`,
            text: text.join(" "),
            keys: [{ key: "Enter", label: "reboot", danger: true }, { key: "Esc", label: "cancel" }]
        };
    }
    const values = a.mode.values || [];
    const choices = MODES.filter(m => values.includes(m.value)).map(m => ({ key: String(m.n), label: m.label + (m.value === a.mode.current ? " ✓" : ""), hl: m.value === a.mode.current, value: m.value }));
    return { title: `Mode for ${row.host}`, text: "", keys: choices.concat([{ key: "Esc", label: "back" }]) };
}

const VERBS = { switch: "switch", boot: "next boot", diff: "diff", mode: "mode", reboot: "reboot", ssh: "ssh" };

function notAllowed(row, name) {
    const act = row.actions && row.actions[name];
    return `${VERBS[name]}: ${act && act.reason ? act.reason : "not offered"}`;
}

function allowed(row, name) {
    return !!(row.actions && row.actions[name] && row.actions[name].allowed);
}

// What a key does. `key` is "S" … "A", "Enter", "Esc", "1".."3", "F5".
// `ask` is the open question ({ host, what }) or null; `row` the selected
// host's row or null; `runUrl` the build run's address or "".
// Returns { kind: "send", cmd, keepAsk } | { kind: "ask", what } |
// { kind: "cancel" } | { kind: "close" } | { kind: "say", text } |
// { kind: "info" } | { kind: "open", url } | { kind: "refresh" } |
// { kind: "none" }.
function decide(row, ask, key, runUrl) {
    if (ask && row && ask.host === row.host) {
        if (key === "Esc")
            return { kind: "cancel" };
        if (ask.what === "switch") {
            if (key === "Enter") {
                if (!allowed(row, "switch"))
                    return { kind: "say", text: notAllowed(row, "switch"), cancel: true };
                const cmd = { cmd: "switch", host: row.host };
                if (row.actions.switch.generation)
                    cmd.generation = row.actions.switch.generation;
                return { kind: "send", cmd };
            }
            if (key === "D")
                return allowed(row, "diff") ? { kind: "send", cmd: { cmd: "diff", host: row.host }, keepAsk: true } : { kind: "say", text: notAllowed(row, "diff") };
            return { kind: "none" };
        }
        if (ask.what === "reboot") {
            if (key === "Enter")
                return allowed(row, "reboot") ? { kind: "send", cmd: { cmd: "reboot", host: row.host } } : { kind: "say", text: notAllowed(row, "reboot"), cancel: true };
            return { kind: "none" };
        }
        if (ask.what === "mode") {
            if (!allowed(row, "mode"))
                return { kind: "say", text: notAllowed(row, "mode"), cancel: true };
            const choice = question(row, "mode").keys.find(k => k.key === key && k.value);
            if (!choice)
                return { kind: "none" };
            if (choice.value === row.actions.mode.current)
                return { kind: "cancel" };
            return { kind: "send", cmd: { cmd: "mode", host: row.host, value: choice.value } };
        }
        return { kind: "none" };
    }
    if (key === "Esc")
        return { kind: "close" };
    if (key === "F5")
        return { kind: "refresh" };
    if (key === "O")
        return runUrl ? { kind: "open", url: runUrl } : { kind: "say", text: "No build run to open." };
    if (!row)
        return { kind: "none" };
    switch (key) {
    case "S":
        return allowed(row, "switch") ? { kind: "ask", what: "switch" } : { kind: "say", text: notAllowed(row, "switch") };
    case "B":
        return allowed(row, "boot") ? { kind: "send", cmd: { cmd: "boot", host: row.host, generation: row.actions.boot.generation } } : { kind: "say", text: notAllowed(row, "boot") };
    case "D":
        return allowed(row, "diff") ? { kind: "send", cmd: { cmd: "diff", host: row.host } } : { kind: "say", text: notAllowed(row, "diff") };
    case "M":
        return allowed(row, "mode") ? { kind: "ask", what: "mode" } : { kind: "say", text: notAllowed(row, "mode") };
    case "R":
        return allowed(row, "reboot") ? { kind: "ask", what: "reboot" } : { kind: "say", text: notAllowed(row, "reboot") };
    case "T":
        return allowed(row, "ssh") ? { kind: "send", cmd: { cmd: "ssh", host: row.host } } : { kind: "say", text: notAllowed(row, "ssh") };
    case "I":
        return hasMore(row) ? { kind: "info" } : { kind: "say", text: "info: nothing more to show" };
    case "A":
        return { kind: "send", cmd: { cmd: "attach", host: row.host } };
    }
    return { kind: "none" };
}

// The host selected after a navigation key, from `names` in drawn order.
function move(names, selected, key) {
    if (!names.length)
        return "";
    const i = names.indexOf(selected);
    if (key === "Home")
        return names[0];
    if (key === "End")
        return names[names.length - 1];
    if (i < 0)
        return names[0];
    if (key === "Up")
        return names[Math.max(0, i - 1)];
    if (key === "Down")
        return names[Math.min(names.length - 1, i + 1)];
    return selected;
}

// The footer text for an action event that needs one, or "": refusals,
// and windows that failed to open.
function footer(ev) {
    if (ev.event !== "action")
        return "";
    const name = VERBS[ev.action] || ev.action || "command";
    if (ev.state === "refused") {
        if (ev.reason === "read-only")
            return `${name}: refused, the helper is read-only.`;
        if (ev.reason === "no-session")
            return `No output: nothing has run on ${ev.host} yet.`;
        return `${name}: refused, ${ev.why || ev.reason}.`;
    }
    if (ev.state === "failed" && !SESSION_ACTIONS.includes(ev.action))
        return `${name}: the window did not open (${ev.reason || "unknown error"}).`;
    return "";
}

// The bar item: { count, dim }, count 0 meaning no number.
function barView(st) {
    const names = Object.keys(st.rows);
    if (single(st) !== "" || names.length === 0)
        return { count: 0, dim: true };
    return { count: names.filter(n => st.rows[n].counts).length, dim: false };
}

if (typeof module !== "undefined")
    module.exports = { SESSION_ACTIONS, MODES, initial, apply, sent, single, order, checking, checked, liveText, pipeline, glyph, modePill, infoLines, actionLine, keys, rowView, question, decide, move, footer, barView };
