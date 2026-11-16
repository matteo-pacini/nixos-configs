// The Tailscale panel's decisions: what a `tailscale status --json` call
// means, and everything the panel and the bar draw from it. Plain JavaScript
// so node can run it too. Times are milliseconds since the epoch, always
// passed in.
//
// Contract:
//
// read(raw, previous, now) -> answer
//   raw: { stdout, exit, stderr, timedOut, light }, one finished call;
//   `light` for `--peers=false`. previous: the last answer, or initial().
//   answer: { state, at, status, light, exit, stderr, good }. `state` is the
//   number of the row in the design's table 2a (1 to 15); `status` the
//   parsed JSON when the call gave one; `good` { status, at } is the last
//   full (not light) answer that parsed, kept across failures.
//
// bar(answer, open, now) -> { look: "on" | "off" | "attention", colour };
//   colour "purple" while the panel is open.
//
// view(answer, mesh, now, ui) -> {
//   header: { word, colour, meta },          meta "read only" | "as of 14:02"
//   strips: [{ tone, text, parts: [{ text, code }] }],  in drawn order
//   versionLine: "" | text (yellow line),
//   note: "" | text drawn in place of the list,
//   well: null | { parts: [{ text, tone, bold }] },     tone "" | "orange"
//   live: bool,                              rows from a live state
//   groups: [{ title, rows: [row] }],        empty groups left out
//   ids: [id] in drawn order, selected: id | "",
//   chooser: null | { id, title, keys: [{ key, label }] },
//   hints: [[key, label]],                   for KeyHints
//   bar: as bar(answer, false, now),
//   login, authUrl                           read by decide()
// }
// row: { id, name, unnamed, glyph, chip: { label, colour }, line, dim,
//   selected, unfolded, details: [{ label, value }], keys: [{ key, label }],
//   copy: [{ key, label, what, value }], ssh: { allowed, reason, alias } }
//
// ui: { selected, unfolded: [id], chooser: id | null }, held by the QML,
// replaced by what decide() returns. initialUi() is the first one.
//
// decide(v, ui, key) -> { kind, ui, ... }, v = view(...). Keys: "Up",
//   "Down", "J", "K", "Home", "End", "Enter", "Y", "T", "O", "F5", "Esc",
//   "1".."4". Kinds:
//   { kind: "ui", ui }                       selection, fold, chooser changed
//   { kind: "copy", ui, text, command, say } run command, flash `say`
//   { kind: "open", ui, url, command }
//   { kind: "ssh", ui, alias, command }      run command, close the panel
//   { kind: "refresh", ui } | { kind: "close", ui }
//   { kind: "say", ui, text }                flash text in the footer
//   { kind: "none", ui }
//
// Colours are Theme names plus "dim" (comment), "soft" (Style.soft) and
// "fg" (foreground).
//
// mesh is the parsed ~/.local/share/desk/tailscale/hosts.json, or null:
// { hosts: [{ label, dns, alias, sshd, device }] }.

const DAY = 86400000;
const HOUR = 3600000;
const MINUTE = 60000;

// "Own key expiring" and the Expiring chip.
const EXPIRING = 14 * DAY;

const ADMIN_URL = "https://login.tailscale.com/admin/machines";
const LOGIN_COMMAND = "sudo tailscale login";

// The states of the design's table 2a: header word and its colour.
const STATES = {
    1: { key: "unread", word: "reading…", colour: "dim" },
    2: { key: "no-daemon", word: "not running", colour: "red" },
    3: { key: "failed", word: "error", colour: "red" },
    4: { key: "hung", word: "no answer", colour: "orange" },
    5: { key: "bad-output", word: "bad output", colour: "orange" },
    6: { key: "NoState", word: "loading", colour: "dim" },
    8: { key: "logged-out", word: "logged out", colour: "orange" },
    9: { key: "login-started", word: "logged out", colour: "orange" },
    10: { key: "key-expired", word: "key expired", colour: "red" },
    11: { key: "NeedsMachineAuth", word: "not approved", colour: "orange" },
    12: { key: "Stopped", word: "off", colour: "dim" },
    13: { key: "Starting", word: "connecting", colour: "cyan" },
    14: { key: "Running", word: "connected", colour: "green" },
    15: { key: "unknown", word: "", colour: "orange" }
};

// The states whose answer carries no map, so no rows.
const NO_LIST = [1, 2, 6, 8, 9];
const LOGIN_STATES = [8, 9, 10];
const ATTENTION_STATES = [2, 3, 4, 5, 8, 9, 10, 11, 15];

const COPY = [
    { n: 1, label: "name", what: "name" },
    { n: 2, label: "DNS name", what: "DNS name" },
    { n: 3, label: "IPv4", what: "IPv4 address" },
    { n: 4, label: "IPv6", what: "IPv6 address" }
];

function initial() {
    return { state: 1, at: null, status: null, light: false, exit: 0, stderr: "", good: null };
}

function initialUi() {
    return { selected: "", unfolded: [], chooser: null };
}

function isObject(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

function firstLine(s) {
    return String(s || "").split("\n").map(l => l.trim()).find(l => l !== "") || "";
}

// The state number for a parsed status.
function stateOf(st) {
    const b = st.BackendState;
    if (b === "NoState")
        return 6;
    if (b === "NeedsLogin") {
        const self = isObject(st.Self) ? st.Self : {};
        if (self.Expired || isObject(st.Peer))
            return 10;
        return st.AuthURL ? 9 : 8;
    }
    if (b === "NeedsMachineAuth")
        return 11;
    if (b === "Stopped")
        return 12;
    if (b === "Starting")
        return 13;
    if (b === "Running")
        return 14;
    // InUseOtherUser is never in a status answer (design, 2a row 7); any
    // other value is unknown.
    return 15;
}

function read(raw, previous, now) {
    const prev = previous || initial();
    const out = { state: 0, at: now, status: null, light: !!raw.light, exit: typeof raw.exit === "number" ? raw.exit : 0, stderr: firstLine(raw.stderr), good: prev.good };
    if (raw.timedOut) {
        out.state = 4;
        return out;
    }
    if (out.exit !== 0) {
        const err = String(raw.stderr || "");
        // cli/diag.go: the "(which appears to be running as …)" variant
        // means the daemon runs but the socket failed.
        out.state = err.includes("failed to connect to local tailscaled") && !err.includes("which appears to be running") ? 2 : 3;
        return out;
    }
    let st = null;
    try {
        st = JSON.parse(raw.stdout);
    } catch (e) {
        st = null;
    }
    if (!isObject(st) || typeof st.BackendState !== "string") {
        out.state = 5;
        return out;
    }
    out.status = st;
    out.state = stateOf(st);
    if (!out.light)
        out.good = { status: st, at: now };
    return out;
}

// ---- wording -------------------------------------------------------------

function parseTime(t) {
    if (typeof t !== "string" || t === "")
        return null;
    const ms = Date.parse(t);
    // Go's zero time (0001-01-01) means unset.
    return isNaN(ms) || ms <= 0 ? null : ms;
}

function pad(n) {
    return n < 10 ? "0" + n : String(n);
}

function date(ms) {
    const d = new Date(ms);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function clock(ms) {
    const d = new Date(ms);
    return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// "just now", "N min ago", "N h ago", "N d ago", or the date.
function ago(t, now) {
    const d = now - t;
    if (d < MINUTE)
        return "just now";
    if (d < HOUR)
        return `${Math.floor(d / MINUTE)} min ago`;
    if (d < 48 * HOUR)
        return `${Math.floor(d / HOUR)} h ago`;
    if (d < 60 * DAY)
        return `${Math.floor(d / DAY)} d ago`;
    return date(t);
}

// "in N min", "in N h", "in N d" or "in N months", for a time ahead.
function ahead(t, now) {
    const d = t - now;
    if (d < HOUR)
        return `in ${Math.max(1, Math.floor(d / MINUTE))} min`;
    if (d < 48 * HOUR)
        return `in ${Math.floor(d / HOUR)} h`;
    if (d < 60 * DAY)
        return `in ${Math.floor(d / DAY)} d`;
    return `in ${Math.floor(d / (30 * DAY))} months`;
}

// A node's key: { kind: "none" | "far" | "expiring" | "expired", text }.
// text is "key expires in 4 months", "key expired 3 d ago", or "" for none.
function keyState(node, now) {
    const exp = parseTime(node.KeyExpiry);
    if (node.Expired)
        return { kind: "expired", text: exp !== null && exp <= now ? `key expired ${ago(exp, now)}` : "key expired" };
    if (exp === null)
        return { kind: "none", text: "" };
    if (exp <= now)
        return { kind: "expired", text: `key expired ${ago(exp, now)}` };
    return { kind: exp - now <= EXPIRING ? "expiring" : "far", text: `key expires ${ahead(exp, now)}` };
}

// Decimal units; one decimal under 10, none from 10 up; 0 is "none yet".
function bytes(n) {
    if (typeof n !== "number" || !(n > 0))
        return "none yet";
    if (n < 1000)
        return `${Math.round(n)} B`;
    const units = ["kB", "MB", "GB", "TB"];
    let v = n / 1000;
    let i = 0;
    while (i < units.length - 1 && Math.round(v * 10) / 10 >= 1000) {
        v /= 1000;
        i++;
    }
    const r = Math.round(v * 10) / 10;
    return r < 10 ? `${r.toFixed(1)} ${units[i]}` : `${Math.round(v)} ${units[i]}`;
}

function shortVersion(v) {
    return typeof v === "string" ? v.split("-")[0] : "";
}

// ---- names ---------------------------------------------------------------

function list(v) {
    return Array.isArray(v) ? v.filter(x => typeof x === "string" && x !== "") : [];
}

function stripDot(s) {
    return typeof s === "string" ? s.replace(/\.$/, "") : "";
}

function suffixOf(st) {
    const t = isObject(st.CurrentTailnet) ? st.CurrentTailnet.MagicDNSSuffix : "";
    return (typeof t === "string" && t) || (typeof st.MagicDNSSuffix === "string" ? st.MagicDNSSuffix : "");
}

function meshHosts(mesh) {
    return isObject(mesh) && Array.isArray(mesh.hosts) ? mesh.hosts.filter(h => isObject(h) && typeof h.dns === "string" && typeof h.label === "string") : [];
}

// The mesh host a node is, matched by its full MagicDNS name, or null.
function meshHost(node, mesh) {
    const dns = stripDot(node.DNSName).toLowerCase();
    if (!dns)
        return null;
    return meshHosts(mesh).find(h => stripDot(h.dns).toLowerCase() === dns) || null;
}

// { name, unnamed } for a node, from section 5's rules.
function nodeName(node, st, mesh) {
    const host = meshHost(node, mesh);
    if (host)
        return { name: host.label, unnamed: false };
    let dns = stripDot(node.DNSName);
    const suffix = suffixOf(st);
    if (dns && suffix && dns.toLowerCase().endsWith("." + suffix.toLowerCase()))
        dns = dns.slice(0, dns.length - suffix.length - 1);
    if (dns)
        return { name: dns, unnamed: false };
    if (typeof node.HostName === "string" && node.HostName)
        return { name: node.HostName, unnamed: false };
    return { name: "unnamed device", unnamed: true };
}

function glyphFor(node, host) {
    if (host)
        return host.device === "server" ? "▤" : host.device === "laptop" ? "▭" : "▣";
    return node.OS === "android" || node.OS === "iOS" ? "▯" : "◫";
}

function ipv4(ips) {
    return ips.find(a => !a.includes(":")) || "";
}

function ipv6(ips) {
    return ips.find(a => a.includes(":")) || "";
}

// ---- rows ----------------------------------------------------------------

// Whether `tailscale status` hides the node (cli/status.go).
function hidden(node) {
    if (node.ShareeNode)
        return true;
    return !!node.ExitNodeOption && !node.ExitNode && typeof node.DNSName === "string" && node.DNSName.endsWith("mullvad.ts.net.");
}

function tagsOf(node) {
    return list(node.Tags);
}

function sharedIn(node, st) {
    if (node.AltSharerUserID)
        return true;
    const self = isObject(st.Self) ? st.Self : null;
    if (tagsOf(node).length || !self || self.UserID === undefined)
        return false;
    return node.UserID !== self.UserID;
}

// The path while online and active: "direct" | "peer relay" | "relayed" |
// "none"; "" when not active.
function pathOf(node) {
    if (!node.Active)
        return "";
    if (node.CurAddr)
        return "direct";
    if (node.PeerRelay)
        return "peer relay";
    if (node.Relay)
        return "relayed";
    return "none";
}

// The one chip, by the design's table 2d.
function chipFor(node, now) {
    const key = keyState(node, now);
    const online = node.Online === true;
    if (key.kind === "expired")
        return { label: "Expired", colour: "red" };
    if (node.ExitNode && !online)
        return { label: "Exit node down", colour: "red" };
    if (key.kind === "expiring")
        return { label: "Expiring", colour: "orange" };
    if (!online)
        return { label: "Offline", colour: "dim" };
    if (node.ExitNode)
        return { label: "Exit node", colour: "cyan" };
    const path = pathOf(node);
    if (path === "direct")
        return { label: "Direct", colour: "green" };
    if (path === "peer relay")
        return { label: "Peer relay", colour: "cyan" };
    if (path === "relayed")
        return { label: "Relayed", colour: "yellow" };
    if (path === "none")
        return { label: "No path", colour: "orange" };
    return { label: "Idle", colour: "soft" };
}

function routesText(n) {
    return n === 1 ? "routes 1 subnet" : `routes ${n} subnets`;
}

// The second line, by the design's section 2e.
function lineFor(node, st, now) {
    const parts = [];
    const online = node.Online === true;
    const ips = list(node.TailscaleIPs);
    if (typeof node.OS === "string" && node.OS)
        parts.push(node.OS);
    if (online)
        parts.push(ipv4(ips) || ips[0] || "no address");
    else {
        const seen = parseTime(node.LastSeen);
        parts.push(seen === null ? "last seen unknown" : `last seen ${ago(seen, now)}`);
    }
    if (online && pathOf(node) === "relayed")
        parts.push(`via ${node.Relay}`);
    const key = keyState(node, now);
    if (key.text)
        parts.push(key.text);
    if (sharedIn(node, st))
        parts.push("shared in");
    if (tagsOf(node).length)
        parts.push("tagged");
    if (node.ExitNodeOption)
        parts.push("offers exit node");
    const routes = list(node.PrimaryRoutes);
    if (routes.length)
        parts.push(routesText(routes.length));
    return parts.join(" · ");
}

function detailsFor(node, st, host, now) {
    const out = [];
    const online = node.Online === true;
    const dns = stripDot(node.DNSName);
    if (dns)
        out.push({ label: "dns", value: dns });
    const ips = list(node.TailscaleIPs);
    out.push({ label: "addresses", value: ips.length ? ips.join(" · ") : "none" });
    if (online) {
        const path = pathOf(node);
        let text;
        if (path === "direct")
            text = `direct, ${node.CurAddr}`;
        else if (path === "peer relay")
            text = "peer relay";
        else if (path === "relayed")
            text = `relayed via ${node.Relay}`;
        else if (path === "none")
            text = "no path";
        else {
            const wrote = parseTime(node.LastWrite);
            text = wrote === null ? "nothing sent yet" : `idle, last sent ${ago(wrote, now)}`;
        }
        out.push({ label: "path", value: text });
    }
    if (typeof node.Relay === "string" && node.Relay)
        out.push({ label: "home relay", value: node.Relay });
    out.push({ label: "traffic", value: `received ${bytes(node.RxBytes)} · sent ${bytes(node.TxBytes)}` });
    const key = keyState(node, now);
    out.push({ label: "key", value: key.text ? key.text.replace(/^key /, "") : "never expires" });
    const tags = tagsOf(node);
    out.push({ label: "owner", value: tags.length ? `tagged: ${tags.join(", ")}` : sharedIn(node, st) ? "shared in" : "you" });
    const offers = [];
    if (node.ExitNodeOption)
        offers.push("exit node");
    offers.push(...list(node.PrimaryRoutes));
    if (offers.length)
        out.push({ label: "offers", value: offers.join(" · ") });
    if (host && host.sshd && host.alias)
        out.push({ label: "ssh", value: host.alias });
    return out;
}

function copyFor(node, name) {
    const ips = list(node.TailscaleIPs);
    const values = [name.unnamed ? "" : name.name, stripDot(node.DNSName), ipv4(ips), ipv6(ips)];
    return COPY.filter((c, i) => values[i] !== "").map(c => ({ key: String(c.n), label: c.label, what: c.what, value: values[c.n - 1] }));
}

// Whether T may open ssh to the node, and why not.
function sshFor(node, host, name, live) {
    if (!host)
        return { allowed: false, reason: "ssh: not a mesh host", alias: "" };
    if (!host.sshd || !host.alias)
        return { allowed: false, reason: `ssh: ${name} does not run sshd`, alias: "" };
    if (!live)
        return { allowed: false, reason: "ssh: the device list is not live", alias: "" };
    if (node.Online !== true)
        return { allowed: false, reason: `ssh: ${name} is offline`, alias: "" };
    return { allowed: true, reason: "", alias: host.alias };
}

// The groups before selection: [{ title, rows }], with rows not yet keyed
// to the ui.
function groupsFor(st, mesh, now, live) {
    const peers = isObject(st.Peer) ? Object.keys(st.Peer).map(k => st.Peer[k]).filter(isObject) : [];
    const mine = [];
    const other = [];
    for (const node of peers) {
        if (hidden(node))
            continue;
        const host = meshHost(node, mesh);
        const name = nodeName(node, st, mesh);
        const chip = chipFor(node, now);
        const row = {
            id: typeof node.ID === "string" && node.ID ? node.ID : String(node.PublicKey || name.name),
            name: name.name,
            unnamed: name.unnamed,
            online: node.Online === true,
            glyph: glyphFor(node, host),
            chip: live ? chip : { label: chip.label, colour: "dim" },
            line: lineFor(node, st, now),
            dim: !live || node.Online !== true,
            allDetails: detailsFor(node, st, host, now),
            copy: copyFor(node, name),
            ssh: sshFor(node, host, name.name, live)
        };
        (host ? mine : other).push(row);
    }
    const sort = rows => rows.sort((a, b) => {
        if (a.online !== b.online)
            return a.online ? -1 : 1;
        const x = a.name.toLowerCase();
        const y = b.name.toLowerCase();
        return x < y ? -1 : x > y ? 1 : a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    });
    const out = [];
    if (mine.length)
        out.push({ title: "MY HOSTS", rows: sort(mine) });
    if (other.length)
        out.push({ title: "OTHER DEVICES", rows: sort(other) });
    return out;
}

// ---- the panel as a whole --------------------------------------------------

function strip(tone, parts) {
    const p = parts.map(x => typeof x === "string" ? { text: x, code: false } : { text: x.code, code: true });
    return { tone, text: p.map(x => x.text).join(""), parts: p };
}

function stateStrip(answer, rowsShown) {
    const st = answer.status;
    switch (answer.state) {
    case 2:
        return strip("red", ["tailscaled is not running. It is enabled in Nix; ", { code: "systemctl status tailscaled" }, " says why it stopped."]);
    case 3:
        return strip("red", [`tailscale status failed (exit ${answer.exit})` + (answer.stderr ? `: ${answer.stderr}` : ".")]);
    case 4:
        return strip("orange", ["tailscale status did not answer within 10 s and was stopped. Trying again in 5 s."]);
    case 5:
        return strip("orange", ["tailscale status printed something that is not status JSON. Trying again in 5 s."]);
    case 6:
        return strip("dim", ["The daemon is loading its state and has not reached the coordination server yet."]);
    case 8:
        return strip("orange", ["Logged out. This panel cannot log in; run ", { code: LOGIN_COMMAND }, " in a terminal (Y copies it)."]);
    case 9:
        return strip("orange", ["A login was started. Finish it in the browser: O opens the login page."]);
    case 10:
        return strip("red", ["This computer's key expired, so it is off the tailnet. Log in again with ", { code: LOGIN_COMMAND }, " (Y copies it)."]);
    case 11:
        return strip("orange", ["This computer is waiting for a tailnet admin to approve it. O opens the admin console."]);
    case 12:
        return strip("dim", ["Tailscale is off (", { code: "tailscale down" }, rowsShown ? "). Devices below are from before; turning it on needs " : "). Turning it on needs ", { code: "sudo tailscale up" }, "."]);
    case 15:
        return strip("orange", [`Tailscale reports a state this panel does not know: ${st.BackendState}.`]);
    }
    return null;
}

function selfOf(st) {
    return isObject(st.Self) ? st.Self : null;
}

// The exit node's name for the strips, or "".
function exitName(st, mesh) {
    const e = st.ExitNodeStatus;
    const peers = isObject(st.Peer) ? Object.keys(st.Peer).map(k => st.Peer[k]).filter(isObject) : [];
    const node = peers.find(p => p.ID === e.ID);
    return node ? nodeName(node, st, mesh).name : "";
}

// The lines of the design's table 2b that are strips, in its order.
function overlayStrips(st, mesh, now) {
    const out = [];
    for (const h of list(st.Health))
        out.push(strip("orange", [h]));
    const self = selfOf(st);
    if (self) {
        const exp = parseTime(self.KeyExpiry);
        if (!self.Expired && exp !== null && exp > now && exp - now <= EXPIRING)
            out.push(strip("orange", [`This computer's key expires ${ahead(exp, now)}. Renew it in the admin console (O).`]));
    }
    if (isObject(st.ExitNodeStatus)) {
        const name = exitName(st, mesh);
        if (st.ExitNodeStatus.Online)
            out.push(strip("cyan", [`Internet traffic leaves through ${name || "an exit node"}.`]));
        else
            out.push(strip("red", [name ? `Exit node ${name} is offline: internet traffic is not getting out.` : "The exit node is offline: internet traffic is not getting out."]));
    }
    const cv = isObject(st.ClientVersion) ? st.ClientVersion : null;
    if (cv && cv.UrgentSecurityUpdate)
        out.push(strip("red", [`Tailscale says ${shortVersion(st.Version) || "this version"} misses an urgent security fix. It comes with a flake update.`]));
    return out;
}

function versionLine(st) {
    const cv = isObject(st.ClientVersion) ? st.ClientVersion : null;
    if (cv && cv.RunningLatest === false && typeof cv.LatestVersion === "string" && cv.LatestVersion)
        return `${cv.LatestVersion} exists · comes with a flake update`;
    return "";
}

function wellFor(st, mesh, now) {
    const self = selfOf(st);
    if (!self)
        return null;
    const parts = [{ text: nodeName(self, st, mesh).name, tone: "", bold: true }];
    const ips = list(self.TailscaleIPs).length ? list(self.TailscaleIPs) : list(st.TailscaleIPs);
    const addr = ipv4(ips) || ips[0] || "";
    const version = shortVersion(st.Version);
    if (addr) {
        parts.push({ text: addr, tone: "", bold: false });
        if (isObject(st.CurrentTailnet))
            parts.push({ text: `· MagicDNS ${st.CurrentTailnet.MagicDNSEnabled ? "on" : "off"}`, tone: "", bold: false });
        if (st.BackendState === "Running" && self.Online !== true)
            parts.push({ text: "· control: not connected", tone: "orange", bold: false });
        const key = keyState(self, now);
        if (key.kind === "none")
            parts.push({ text: "· key never expires", tone: "", bold: false });
        else
            parts.push({ text: `· ${key.text}`, tone: key.kind === "far" ? "" : "orange", bold: false });
    }
    if (version)
        parts.push({ text: `· ${version}`, tone: "", bold: false });
    return { parts };
}

// Whether a status, light or full, needs the user (design, section 3).
function needsAttention(answer, now) {
    if (ATTENTION_STATES.includes(answer.state))
        return true;
    const st = answer.status;
    if (!st)
        return false;
    if (list(st.Health).length)
        return true;
    const self = selfOf(st);
    if (self) {
        if (st.BackendState === "Running" && self.Online !== true)
            return true;
        const k = keyState(self, now);
        if (k.kind === "expiring" || k.kind === "expired")
            return true;
    }
    if (isObject(st.ExitNodeStatus) && !st.ExitNodeStatus.Online)
        return true;
    return !!(isObject(st.ClientVersion) && st.ClientVersion.UrgentSecurityUpdate);
}

// The bar item. `now` is needed for this computer's key expiry.
function bar(answer, open, now) {
    let look;
    if (needsAttention(answer, now))
        look = "attention";
    else
        look = answer.state === 14 ? "on" : "off";
    const colour = open ? "purple" : look === "attention" ? "orange" : look === "on" ? "fg" : "dim";
    return { look, colour };
}

// Where the rows come from: { status, at, live, stale } or null.
function rowSource(answer) {
    const n = answer.state;
    if (NO_LIST.includes(n))
        return null;
    if (n >= 3 && n <= 5)
        return answer.good ? { status: answer.good.status, at: answer.good.at, live: false, stale: true } : null;
    if (answer.light)
        return answer.good ? { status: answer.good.status, at: answer.good.at, live: false, stale: true } : null;
    return { status: answer.status, at: answer.at, live: n === 13 || n === 14, stale: false };
}

function keep(ids, selected) {
    return ids.includes(selected) ? selected : ids.length ? ids[0] : "";
}

function view(answer, mesh, now, ui) {
    const u = ui || initialUi();
    const n = answer.state;
    const st = answer.status;
    const def = STATES[n];
    const src = rowSource(answer);
    const groups0 = src ? groupsFor(src.status, mesh, now, src.live) : [];
    const ids = [];
    groups0.forEach(g => g.rows.forEach(r => ids.push(r.id)));
    const selected = keep(ids, u.selected);
    const login = LOGIN_STATES.includes(n);

    const groups = groups0.map(g => ({
        title: g.title,
        rows: g.rows.map(r => {
            const sel = r.id === selected;
            const unfolded = u.unfolded.includes(r.id);
            const keys = [];
            if (sel) {
                keys.push({ key: "Enter", label: unfolded ? "fold" : "details" });
                if (!login && r.copy.length)
                    keys.push({ key: "Y", label: "copy" });
                if (r.ssh.allowed)
                    keys.push({ key: "T", label: "ssh" });
            }
            return {
                id: r.id,
                name: r.name,
                unnamed: r.unnamed,
                glyph: r.glyph,
                chip: r.chip,
                line: r.line,
                dim: r.dim,
                selected: sel,
                unfolded,
                details: unfolded ? r.allDetails : [],
                keys,
                copy: r.copy,
                ssh: r.ssh
            };
        })
    }));

    const rowsShown = ids.length > 0;
    const strips = [];
    const first = stateStrip(answer, rowsShown);
    if (first)
        strips.push(first);
    if (st)
        strips.push(...overlayStrips(st, mesh, now));

    let chooser = null;
    if (u.chooser !== null && u.chooser === selected && !login) {
        const row = groups.reduce((a, g) => a.concat(g.rows), []).find(r => r.id === selected);
        if (row && row.copy.length)
            chooser = { id: row.id, title: `Copy from ${row.name}`, keys: row.copy.map(c => ({ key: c.key, label: c.label })).concat([{ key: "Esc", label: "back" }]) };
    }

    const hints = [];
    if (chooser) {
        const nums = chooser.keys.filter(k => k.key !== "Esc").map(k => k.key);
        hints.push([nums.length > 1 ? `${nums[0]}–${nums[nums.length - 1]}` : nums[0], "copy"]);
        hints.push(["Esc", "back"]);
    } else {
        if (ids.length > 1)
            hints.push(["↑↓ J K", "device"]);
        if (login)
            hints.push(["Y", "copy command"]);
        hints.push(["O", st && st.AuthURL ? "login page" : "admin console"]);
        hints.push(["F5", n >= 2 && n <= 5 ? "retry" : "refresh"]);
        hints.push(["Esc", "close"]);
    }

    return {
        header: {
            word: n === 15 ? String(st.BackendState) : def.word,
            colour: def.colour,
            meta: src && src.stale ? `as of ${clock(src.at)}` : "read only"
        },
        strips,
        versionLine: st ? versionLine(st) : "",
        note: n === 1 ? "Reading Tailscale…" : "",
        well: st ? wellFor(st, mesh, now) : null,
        live: !!(src && src.live),
        groups,
        ids,
        selected,
        chooser,
        hints,
        bar: bar(answer, false, now),
        login,
        authUrl: st && typeof st.AuthURL === "string" ? st.AuthURL : ""
    };
}

// ---- keys ----------------------------------------------------------------

function withUi(ui, changes) {
    return Object.assign({}, ui, changes);
}

// The selection after a navigation key, from `ids` in drawn order.
function move(ids, selected, key) {
    if (!ids.length)
        return "";
    const i = ids.indexOf(selected);
    if (key === "Home")
        return ids[0];
    if (key === "End")
        return ids[ids.length - 1];
    if (i < 0)
        return ids[0];
    if (key === "Up" || key === "K")
        return ids[Math.max(0, i - 1)];
    if (key === "Down" || key === "J")
        return ids[Math.min(ids.length - 1, i + 1)];
    return selected;
}

function selectedRow(v) {
    for (const g of v.groups)
        for (const r of g.rows)
            if (r.id === v.selected)
                return r;
    return null;
}

function copyAction(ui, text, say) {
    return { kind: "copy", ui, text, command: ["wl-copy", "--", text], say };
}

function decide(v, ui, key) {
    const u = withUi(ui || initialUi(), { selected: v.selected });
    if (v.chooser) {
        if (key === "Esc")
            return { kind: "ui", ui: withUi(u, { chooser: null }) };
        const row = selectedRow(v);
        const c = row ? row.copy.find(x => x.key === key) : null;
        if (c)
            return copyAction(withUi(u, { chooser: null }), c.value, `Copied the ${c.what} of ${row.name}.`);
        return { kind: "none", ui: u };
    }
    const closed = withUi(u, { chooser: null });
    if (key === "Esc")
        return { kind: "close", ui: closed };
    if (key === "F5")
        return { kind: "refresh", ui: u };
    if (key === "O") {
        const url = v.authUrl || ADMIN_URL;
        return { kind: "open", ui: u, url, command: ["uwsm", "app", "--", "xdg-open", url] };
    }
    if (["Up", "Down", "J", "K", "Home", "End"].includes(key)) {
        if (v.ids.length < 2)
            return { kind: "none", ui: u };
        return { kind: "ui", ui: withUi(u, { selected: move(v.ids, v.selected, key) }) };
    }
    if (key === "Y" && v.login)
        return copyAction(u, LOGIN_COMMAND, "Copied the login command.");
    const row = selectedRow(v);
    if (!row)
        return { kind: "none", ui: u };
    switch (key) {
    case "Enter": {
        const open = u.unfolded.includes(row.id);
        return { kind: "ui", ui: withUi(u, { unfolded: open ? u.unfolded.filter(id => id !== row.id) : u.unfolded.concat([row.id]) }) };
    }
    case "Y":
        return row.copy.length ? { kind: "ui", ui: withUi(u, { chooser: row.id }) } : { kind: "say", ui: u, text: `copy: nothing to copy from ${row.name}` };
    case "T":
        if (!row.ssh.allowed)
            return { kind: "say", ui: u, text: row.ssh.reason };
        return { kind: "ssh", ui: u, alias: row.ssh.alias, command: ["uwsm", "app", "--", "ghostty", `--title=Tailscale: ${row.name}`, "-e", "ssh", row.ssh.alias] };
    }
    return { kind: "none", ui: u };
}

if (typeof module !== "undefined")
    module.exports = { ADMIN_URL, initial, initialUi, read, bar, view, decide, ago, keyState, bytes, shortVersion };
