// desk-nest's fakes (nest/fakes) run as the shell runs them, their output
// read by the panels' own libraries: every fixture in nest/fixtures/index,
// a switch while a fake runs, the commands the fakes answer; then the stubs
// (log the call, print nothing, write nothing else) and the launcher's
// nest-place and nest-notify.
// usage: node test-nest-fakes.js <hyprland dir> <quickshell dir> <work dir>
//   <hyprland dir> holds nest/ (fakes.py runnable as it is) and tests/;
//   nest/fakes/bin must be first on PATH, a recording `gdbus` after it.
"use strict";
const fs = require("fs");
const path = require("path");
const { spawn, spawnSync } = require("child_process");

const [hl, qs, work] = process.argv.slice(2).map(p => path.resolve(p));
const state = path.join(work, "state");
const tests = path.join(hl, "tests");
fs.mkdirSync(path.join(state, "control"), { recursive: true });
const env = Object.assign({}, process.env, { NEST_STATE: state });
const lib = n => require(path.join(qs, n));
const W = lib("weather/weather.js"), O = lib("office/office.js"), F = lib("fleet/fleet.js");
const T = lib("tokens/tokens.js"), S = lib("tailscale/tailscale.js");
const control = (p, v) => fs.writeFileSync(path.join(state, "control", p), v + "\n");
const sleep = ms => new Promise(r => setTimeout(r, ms));
const logText = () => fs.existsSync(path.join(state, "fakes.log")) ? fs.readFileSync(path.join(state, "fakes.log"), "utf8") : "";

let failed = 0;
function check(name, ok, detail) {
    if (ok) {
        console.log(`ok   ${name}`);
    } else {
        failed++;
        console.log(`FAIL ${name}${detail === undefined ? "" : ": " + detail}`);
    }
}
function run(cmd, args, opts) {
    return spawnSync(cmd, args, Object.assign({ env, encoding: "utf8", input: "" }, opts));
}
const lines = out => out.split("\n").filter(Boolean);

// Starts a fake, runs script(write) while it lives, then closes its stdin
// and returns its stdout lines.
async function session(name, script) {
    const p = spawn(name, [], { env });
    let out = "";
    p.stdout.on("data", d => out += d);
    await script(l => p.stdin.write(JSON.stringify(l) + "\n"));
    p.stdin.end();
    await new Promise(r => p.on("close", r));
    return lines(out);
}

// index: "<panel> <name> [place|inside] [description]", defaults first.
const index = {};
for (const raw of fs.readFileSync(path.join(hl, "nest/fixtures/index"), "utf8").split("\n")) {
    const w = raw.split("#")[0].trim().split(/\s+/);
    if (w.length >= 2)
        (index[w[0]] = index[w[0]] || []).push({ name: w[1], flag: ["place", "inside"].includes(w[2]) ? w[2] : null });
}
const names = p => (index[p] || []).map(e => e.name);

(async () => {
    const now = () => Date.now() / 1000;

    // ---- the index against the fixtures it names --------------------------
    for (const p of ["weather", "office", "fleet"]) {
        const files = fs.readdirSync(path.join(tests, `${p}-panel/fixtures`)).filter(f => f.endsWith(".jsonl")).map(f => f.slice(0, -6));
        const missing = files.filter(f => !names(p).includes(f));
        check(`index lists every ${p}-panel fixture`, missing.length === 0, missing.join(" "));
        const unknown = names(p).filter(n => n.split("+").some(x => !files.includes(x)));
        check(`index names only existing ${p} fixtures`, unknown.length === 0, unknown.join(" "));
    }
    const tsFx = n => JSON.parse(fs.readFileSync(path.join(tests, `tailscale-panel/fixtures/${n}.json`), "utf8"));
    const tsWant = ["running", "peers"]
        .concat(Object.keys(tsFx("overlays")).filter(k => k !== "_").map(k => "overlay:" + k))
        .concat(Object.keys(tsFx("states")).map(k => "state:" + k))
        .concat(Object.keys(tsFx("calls")).map(k => "call:" + k));
    check("index lists every tailscale-panel answer, and only those",
          JSON.stringify([...tsWant].sort()) === JSON.stringify([...names("tailscale")].sort()));
    for (const p of Object.keys(index))
        check(`index: ${p} has a default and no name twice`, names(p).length > 0 && new Set(names(p)).size === names(p).length);

    // ---- the names in bin/ --------------------------------------------------
    const bin = path.join(hl, "nest/fakes/bin");
    const own = run("python3", [path.join(hl, "nest/fakes/fakes.py"), "--names"]);
    const inBin = fs.readdirSync(bin).sort();
    check("bin/ holds exactly the names fakes.py answers to",
          JSON.stringify(inBin) === JSON.stringify(lines(own.stdout).sort()), `${inBin.join(" ")} vs ${own.stdout}`);
    const notLinks = inBin.filter(n => fs.readlinkSync(path.join(bin, n)) !== "../fakes.py");
    check("every name in bin/ is a link to ../fakes.py", notLinks.length === 0, notLinks.join(" "));

    // ---- weather ------------------------------------------------------------
    const weather = ls => {
        let st = W.initial();
        for (const l of ls) st = W.apply(st, JSON.parse(l), now());
        return W.view(st, now());
    };
    for (const n of names("weather")) {
        control("weather", n);
        const out = lines(run("desk-weather", ["--config", "/nonexistent"]).stdout);
        let v = null, err = "";
        try {
            v = weather(out);
        } catch (e) {
            err = e.message;
        }
        check(`desk-weather ${n}: ${out.length} lines, read by weather.js`, out.length > 0 && v !== null, err);
    }
    control("weather", names("weather")[0]);
    const hero = v => JSON.stringify(v.hero);
    const first = weather(lines(run("desk-weather", []).stdout));
    const switched = await session("desk-weather", async () => {
        await sleep(700);
        control("weather", "02-snow-night");
        await sleep(1200);
    });
    check("desk-weather default: light rain, with warnings",
          /Light rain/.test(hero(first)) && first.warnings && first.warnings.length > 0, hero(first));
    check("desk-weather switches fixture while running: snow", /Snow/.test(hero(weather(switched))), hero(weather(switched)));
    check("the switch is logged", /fixture weather -> 02-snow-night/.test(logText()));
    control("weather", names("weather")[0]);
    const radar = await session("desk-weather", async w => {
        await sleep(400);
        w({ cmd: "radar", on: true });
        await sleep(400);
    });
    check("desk-weather answers radar on", radar.some(l => /"event": ?"radar(_error)?"/.test(l)));

    // ---- office -------------------------------------------------------------
    for (const n of names("office")) {
        control("office", n);
        const out = lines(run("desk-mqtt", []).stdout);
        let ok = false, err = "";
        try {
            let os = O.initial(true);
            for (const l of out) os = O.apply(os, JSON.parse(l));
            O.barView(os, Date.now());
            ok = true;
        } catch (e) {
            err = e.message;
        }
        check(`desk-mqtt ${n}: ${out.length} lines, read by office.js`, out.length > 0 && ok, err);
    }
    control("office", "09-live");
    const office = await session("desk-mqtt", async w => {
        await sleep(500);
        w({ id: 1, device: "light", action: "off" });
        await sleep(1300);
    });
    let os = O.initial(true);
    for (const l of office) os = O.apply(os, JSON.parse(l));
    check("desk-mqtt confirms a command and the light follows it",
          office.some(l => /"state": "confirmed"/.test(l)) && O.lightView(os, Date.now(), null).on === false,
          JSON.stringify(O.lightView(os, Date.now(), null)).slice(0, 200));

    // ---- fleet --------------------------------------------------------------
    for (const n of names("fleet")) {
        control("fleet", n);
        const out = lines(run("desk-fleet", ["--read-only"]).stdout);
        let ok = false, err = "";
        try {
            let fs_ = F.initial("running");
            for (const l of out) fs_ = F.apply(fs_, JSON.parse(l));
            F.order(fs_);
            F.barView(fs_);
            ok = true;
        } catch (e) {
            err = e.message;
        }
        check(`desk-fleet ${n}: ${out.length} lines, read by fleet.js`, out.length > 0 && ok, err);
    }
    control("fleet", "hero");
    const fleet = await session("desk-fleet", async w => {
        await sleep(500);
        for (const cmd of ["switch", "boot", "mode", "reboot", "diff", "ssh", "attach"])
            w({ id: cmd, cmd, host: "Nexus" });
        await sleep(300);
    });
    const refused = fleet.filter(l => /"state": "refused", "reason": "read-only"/.test(l)).length;
    check("desk-fleet refuses every action", refused === 7, `${refused} of 7`);

    // ---- tokens -------------------------------------------------------------
    for (const n of names("tokens")) {
        control("tokens", n);
        let ts = T.opened();
        const reqs = ts.effects.filter(e => e.do === "send").map(e => e.req);
        ts = T.helper(ts.state, "running").state;
        const out = await session("desk-tokens", async w => {
            for (const q of reqs) w(q);
            for (const q of [{ req: "projects", period: "today", id: 90 }, { req: "projects", period: "7d", id: 91 },
                             { req: "project", id: 92 }, { req: "days", id: 93 }])
                w(q);
            await sleep(500);
        });
        let ok = false, err = "";
        try {
            for (const l of out) ts = T.event(ts, l).state;
            T.view(ts, T.limits("", now()));
            ok = true;
        } catch (e) {
            err = e.message;
        }
        const answered = [90, 91, 92, 93].every(id => out.some(l => JSON.parse(l).id === id));
        check(`desk-tokens ${n}: the panel's requests and every page answered, read by tokens.js`,
              ok && answered && !out.some(l => /bad-input/.test(l)), err || out.join("\n").slice(0, 300));
    }

    // ---- tailscale ----------------------------------------------------------
    const mesh = JSON.parse(fs.readFileSync(path.join(tests, "tailscale-panel/fixtures/mesh.json"), "utf8"));
    const call = args => {
        const p = run("tailscale", args, { timeout: 2000 });
        return { stdout: p.stdout, stderr: p.stderr, exit: p.status, timedOut: p.signal !== null, light: args.includes("--peers=false") };
    };
    for (const n of names("tailscale")) {
        control("tailscale", n);
        let ok = false, err = "";
        try {
            const a = S.read(call(["status", "--json"]), S.initial(), Date.now());
            S.view(a, mesh, Date.now(), S.initialUi());
            S.bar(a, false, Date.now());
            ok = true;
        } catch (e) {
            err = e.message;
        }
        check(`tailscale ${n}: read by tailscale.js`, ok, err);
    }
    control("tailscale", "running");
    check("tailscale --peers=false leaves out the peers",
          "Peer" in JSON.parse(call(["status", "--json"]).stdout) && !("Peer" in JSON.parse(call(["status", "--json", "--peers=false"]).stdout)));
    control("tailscale", "call:no-daemon");
    const nd = call(["status", "--json"]);
    check("tailscale call:no-daemon fails as tailscale does", nd.exit === 1 && /tailscaled/.test(nd.stderr));

    // ---- network: Network.qml's own command line ----------------------------
    const nq = fs.readFileSync(path.join(qs, "Network.qml"), "utf8");
    const line = (nq.match(/command: \["sh", "-c", "(nmcli [^"]*)"\]/) || [])[1];
    check("Network.qml's nmcli command line found", !!line);
    control("network", "wired");
    const wired = run("sh", ["-c", line]).stdout;
    check("network wired: a device and a default route",
          /GENERAL.DEVICE:enp2s0/.test(wired) && /@route\n\[\{"dst":"default"/.test(wired), JSON.stringify(wired));
    control("network", "none");
    const none = run("sh", ["-c", line]).stdout;
    check("network none: no device, no route", /^@route\n\[\]\n@duplex/.test(none), JSON.stringify(none));

    // ---- bluetooth agent ----------------------------------------------------
    const bt = run("desk-bt-agent", [], { input: '{"answer":"yes"}\n' });
    check("desk-bt-agent: ready, then exit when stdin closes",
          lines(bt.stdout).map(l => JSON.parse(l).event).join(" ") === "ready exit");

    // ---- wrappers -----------------------------------------------------------
    control("cheatsheet", "host");
    const binds = JSON.parse(run("hyprctl", ["-j", "binds"]).stdout);
    check("hyprctl -j binds (host): the captured binds", Array.isArray(binds) && binds.length > 50, binds.length);
    control("lock", "idle");
    const quiet = run("gdbus", ["monitor", "--system", "--dest", "org.freedesktop.login1"], { timeout: 1500 });
    check("gdbus --system monitor is held open and says nothing", quiet.signal === "SIGTERM" && quiet.stdout === "");
    control("lock", "sleep");
    const slept = run("gdbus", ["monitor", "--system", "--dest", "org.freedesktop.login1"], { timeout: 1500 });
    check("gdbus --system monitor says PrepareForSleep for lock sleep",
          slept.signal === "SIGTERM" && /PrepareForSleep \(true,\)/.test(slept.stdout), JSON.stringify(slept.stdout));
    const sysCall = run("gdbus", ["call", "--system", "--dest", "org.freedesktop.login1"]);
    check("gdbus --system call fails", sysCall.status === 1);

    // ---- stubs: log the call, print nothing, write nothing ------------------
    const listing = dir => fs.readdirSync(dir).sort().join(" ");
    const stubs = lines(own.stdout).filter(n => !["desk-weather", "desk-mqtt", "desk-fleet", "desk-tokens", "tailscale",
        "nmcli", "ip", "desk-bt-agent", "gdbus", "hyprctl", "nest-place", "nest-notify"].includes(n));
    // name: [args, exit, stdout]
    const special = {
        systemctl: [["--user", "is-active", "calendar-sync.service"], 3, "inactive\n"],
        "systemd-run": [["--user", "--unit=desk-lock", "--collect", "--quiet", "qs", "-n", "-p", "/x/lock.qml"], 1, ""],
        "systemd-inhibit": [["--what=sleep", "--mode=delay", "cat"], 0, ""],
        cfspeedtest: [[], 1, ""],
        speedtest: [["--format=jsonl"], 1, ""],
        "pw-dump": [[], 0, "[]\n"],
    };
    const cwd = fs.mkdtempSync(path.join(work, "cwd-"));
    const stateBefore = listing(state);
    for (const n of stubs) {
        const [args, exit, stdout] = special[n] || [["--test-arg", "a b"], 0, ""];
        const logBefore = logText();
        const p = run(n, args, { cwd });
        const added = logText().slice(logBefore.length);
        check(`stub ${n}: exit ${exit}, logged, nothing printed`,
              p.status === exit && p.stdout === stdout && added.includes(`${n} stub: ${args.join(" ")}`),
              `exit ${p.status} out ${JSON.stringify(p.stdout)} log ${JSON.stringify(added)}`);
    }
    check("the stubs wrote nothing but the log", listing(cwd) === "" && listing(state) === stateBefore, `${listing(cwd)} | ${listing(state)}`);
    const unknownName = path.join(work, "no-such-tool");
    fs.symlinkSync(path.join(hl, "nest/fakes/fakes.py"), unknownName);
    check("run as an unknown name: exit 127", run(unknownName, []).status === 127);

    // ---- nest-place ---------------------------------------------------------
    const home = path.join(state, "home");
    const events = path.join(home, "cache/desk/calendar/events.jsonl");
    const fixture = fs.readFileSync(path.join(tests, "calendar/panel/fixture-events.jsonl"), "utf8");
    const today = (() => {
        const d = new Date();
        return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
    })();
    check("nest-place calendar fixed: the export as written",
          run("nest-place", ["calendar", "fixed"]).status === 0 && fs.readFileSync(events, "utf8") === fixture);
    run("nest-place", ["calendar", "today"]);
    const head = JSON.parse(fs.readFileSync(events, "utf8").split("\n")[0]);
    check("nest-place calendar today: generated today, same number of days",
          head.generated.startsWith(today) && head.days === JSON.parse(fixture.split("\n")[0]).days, JSON.stringify(head));
    const source = JSON.parse(fs.readFileSync(path.join(home, "data/desk/calendar/source.json"), "utf8"));
    check("nest-place calendar: source.json names a url file that exists", fs.existsSync(source.url_file));
    run("nest-place", ["calendar", "none"]);
    check("nest-place calendar none: no export", !fs.existsSync(events));
    for (const n of names("limits")) {
        const p = run("nest-place", ["limits", n]);
        const text = fs.readFileSync(path.join(home, "runtime/desk/claude-limits.json"), "utf8");
        const d = JSON.parse(text);
        let ok = false, err = "";
        try {
            T.limits(text, now());
            ok = true;
        } catch (e) {
            err = e.message;
        }
        check(`nest-place limits ${n}: written a minute ago, read by tokens.js`,
              p.status === 0 && Math.abs(now() - 60 - d.written_at) < 5 && ok, err);
    }
    const bad = run("nest-place", ["limits", "nope"]);
    check("nest-place refuses a name not in the index", bad.status === 2 && /no place fixture limits nope/.test(bad.stderr));
    const noState = run("nest-place", ["limits", "normal"], { env: Object.assign({}, env, { NEST_STATE: "" }) });
    check("nest-place refuses to run without NEST_STATE", noState.status === 2);
    check("nest-place wrote only under NEST_STATE/home", listing(state).split(" ").every(f => ["control", "fakes.log", "home"].includes(f)));

    // ---- nest-notify --------------------------------------------------------
    const rec = path.join(work, "gdbus-calls");
    for (const n of names("notifications")) {
        if (fs.existsSync(rec))
            fs.rmSync(rec);
        const p = run("nest-notify", [n]);
        const calls = lines(fs.existsSync(rec) ? fs.readFileSync(rec, "utf8") : "");
        const want = JSON.parse(fs.readFileSync(path.join(hl, `nest/fixtures/notifications/${n}.json`), "utf8")).length;
        check(`nest-notify ${n}: ${want} Notify calls on the session bus`,
              p.status === 0 && calls.length === want &&
              calls.every(c => c.startsWith("call --session --dest org.freedesktop.Notifications ") && c.endsWith(" int32 -1")),
              calls.join("\n") + p.stderr);
    }

    console.log(failed ? `${failed} failed` : "all passed");
    process.exit(failed ? 1 : 0);
})().catch(e => {
    console.log("FAIL " + e.stack);
    process.exit(1);
});
