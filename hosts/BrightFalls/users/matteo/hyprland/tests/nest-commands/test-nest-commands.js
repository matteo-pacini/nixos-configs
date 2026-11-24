// Every command the shell can start, read from its source, must be a fake or
// stub in nest/fakes/bin or a harmless command in ./allowlist, so a new
// command cannot reach outside desk-nest unnoticed. Also: nest/dev.qml loads
// exactly shell.qml's components.
// usage: node test-nest-commands.js <quickshell dir> <nest dir> <allowlist>
//
// A command is the first string of an array literal in command position:
// after `command:` or `command =` (both arms of a ternary), inside
// `execDetached(`, or returned by a function named `command`. For
// ["sh", "-c", <script>], the script's commands count too: a string literal,
// or `root.<name>` built from string literals in the same file. Any other
// expression in command position must be a `site` line of the allowlist,
// which says where it resolves; a `site` line that matches nothing fails, so
// the list cannot go stale. A Hyprland dispatch must not exec.
"use strict";
const fs = require("fs");
const path = require("path");

const [qs, nest, allowPath] = process.argv.slice(2).map(p => path.resolve(p));
let failed = 0;
const fail = msg => {
    failed++;
    console.log("FAIL " + msg);
};

// ---- allowlist ------------------------------------------------------------
// harmless <name> <why>
// site <file> <expression> <where it resolves>
const harmless = new Map();
const sites = [];
for (const raw of fs.readFileSync(allowPath, "utf8").split("\n")) {
    const line = raw.trim();
    if (line === "" || line.startsWith("#"))
        continue;
    const w = line.split(/\s+/);
    if (w[0] === "harmless" && w.length >= 3)
        harmless.set(w[1], w.slice(2).join(" "));
    else if (w[0] === "site" && w.length >= 4)
        sites.push({ file: w[1], expr: w[2], used: false });
    else
        fail(`allowlist: cannot read "${line}"`);
}
const faked = new Set(fs.readdirSync(path.join(nest, "fakes/bin")));

// ---- source scan ----------------------------------------------------------
function files(dir) {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => {
        const p = path.join(dir, e.name);
        return e.isDirectory() ? files(p) : /\.(qml|js)$/.test(e.name) ? [p] : [];
    });
}

// The index in `src`, from `i`, of the first character of `stops` outside
// brackets and strings, or of a closing bracket that matches none after `i`.
function end(src, i, stops) {
    let depth = 0, q = null;
    for (let j = i; j < src.length; j++) {
        const c = src[j];
        if (q) {
            if (c === "\\")
                j++;
            else if (c === q)
                q = null;
        } else if (c === '"' || c === "'" || c === "`") {
            q = c;
        } else if ("([{".includes(c)) {
            depth++;
        } else if (")]}".includes(c)) {
            if (depth === 0)
                return j;
            depth--;
        } else if (depth === 0 && stops.includes(c)) {
            return j;
        }
    }
    return src.length;
}

// The text from `i` to the end of its expression.
function expression(src, i) {
    return src.slice(i, end(src, i, ";\n,"));
}

// String literals of a JS expression, unescaped.
function strings(text) {
    const out = [];
    const re = /"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'/g;
    let m;
    while ((m = re.exec(text))) {
        const body = m[1] !== undefined ? m[1] : m[2].replace(/\\'/g, "'").replace(/"/g, '\\"');
        try {
            out.push(JSON.parse('"' + body + '"'));
        } catch (e) {
            out.push(body);
        }
    }
    return out;
}

// Elements of each array literal at the top level of `text` (the arms of a
// ternary, not an argument of a call), as source text.
function arrays(text) {
    const out = [];
    let q = null;
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (q) {
            if (c === "\\")
                i++;
            else if (c === q)
                q = null;
        } else if (c === '"' || c === "'" || c === "`") {
            q = c;
        } else if (c === "(" || c === "{") {
            i = end(text, i + 1, "");
        } else if (c === "[") {
            const close = end(text, i + 1, "");
            const items = [];
            for (let k = i + 1; k < close;) {
                const e = Math.min(end(text, k, ","), close);
                items.push(text.slice(k, e).trim());
                k = e + 1;
            }
            out.push(items);
            i = close;
        }
    }
    return out;
}

const KEYWORDS = new Set(["do", "done", "if", "then", "else", "elif", "fi", "while", "until", "!"]);
// The commands a shell script starts: the first word of each simple
// command, after any keywords; `for` and `case` heads start none. A word
// that is not a plain name (a lone quote left over from "$(…)", a
// redirection) starts none either, except a `$` expansion, a path and a
// quoted word, which are reported as found: the check cannot tell what they
// run.
function scriptCommands(script) {
    const out = [];
    for (const seg of script.replace(/\$\(/g, ";").split(/;|&&|\|\||\||\n/)) {
        const words = seg.trim().split(/\s+/);
        if (words[0] === "for" || words[0] === "case")
            continue;
        while (words.length && KEYWORDS.has(words[0]))
            words.shift();
        if (words[0] !== undefined && /^([A-Za-z_][\w.+-]*|[$/].*|["'].+)$/.test(words[0]))
            out.push(words[0]);
    }
    return out;
}

const found = new Map(); // command -> ["file:line", ...]
function note(cmd, where) {
    if (!found.has(cmd))
        found.set(cmd, []);
    found.get(cmd).push(where);
}

for (const file of files(qs)) {
    const rel = path.relative(qs, file);
    const src = fs.readFileSync(file, "utf8").replace(/^\s*\/\/.*$/gm, m => " ".repeat(m.length));
    const lineOf = i => src.slice(0, i).split("\n").length;
    const starts = [];
    for (const re of [/\bcommand\s*[:=](?!=)\s*/g, /\bexecDetached\(\s*/g, /\bfunction command\b[^{]*\{\s*return\s*/g]) {
        let m;
        while ((m = re.exec(src)))
            starts.push(m.index + m[0].length);
    }
    for (const at of starts) {
        const expr = expression(src, at).trim();
        const where = `${rel}:${lineOf(at)}`;
        const lists = arrays(expr).filter(a => a.length && /^["']/.test(a[0]));
        if (lists.length === 0) {
            const site = sites.find(s => s.file === rel && expr.startsWith(s.expr));
            if (site)
                site.used = true;
            else
                fail(`${where}: command from "${expr.slice(0, 80)}" is not a literal; add a site line to the allowlist saying where it resolves`);
            continue;
        }
        for (const a of lists) {
            const cmd = strings(a[0])[0];
            note(cmd, where);
            if (cmd !== "sh" || strings(a[1] || "")[0] !== "-c")
                continue;
            let script = strings(a[2] || "");
            const ref = /^root\.(\w+)$/.exec(a[2] || "");
            if (ref) {
                const def = new RegExp(`property\\s+\\w+\\s+${ref[1]}\\s*:\\s*`).exec(src);
                script = def ? strings(expression(src, def.index + def[0].length)) : [];
            }
            if (script.length === 0) {
                fail(`${where}: sh -c with a script the check cannot read: ${a[2]}`);
                continue;
            }
            for (const c of scriptCommands(script.join("\n")))
                note(c, `${where} (sh -c)`);
        }
    }
    let m;
    const dispatch = /\bdispatch\(/g;
    while ((m = dispatch.exec(src))) {
        const arg = expression(src, m.index + m[0].length);
        if (/exec/.test(arg))
            fail(`${rel}:${lineOf(m.index)}: a Hyprland dispatch runs a command: ${arg.slice(0, 80)}`);
    }
}

for (const [cmd, where] of [...found].sort()) {
    if (faked.has(cmd))
        console.log(`ok   ${cmd}: fake or stub (${where.length} use${where.length > 1 ? "s" : ""})`);
    else if (harmless.has(cmd))
        console.log(`ok   ${cmd}: harmless, ${harmless.get(cmd)}`);
    else
        fail(`${cmd} (${where.join(", ")}) is neither in nest/fakes/bin nor harmless in the allowlist`);
}
for (const s of sites.filter(s => !s.used))
    fail(`allowlist: site ${s.file} ${s.expr} matches no command site`);
for (const name of harmless.keys())
    if (!found.has(name))
        fail(`allowlist: harmless ${name} is not run by the shell`);

// ---- dev.qml against shell.qml --------------------------------------------
const shell = fs.readFileSync(path.join(qs, "shell.qml"), "utf8");
const want = [...shell.matchAll(/^ {4}([A-Z]\w*) \{\}$/gm)].map(m => m[1]);
const dev = fs.readFileSync(path.join(nest, "dev.qml"), "utf8");
const all = strings((/property list<string> all: (\[[^\]]*\])/.exec(dev) || [, ""])[1]);
const loaders = [...dev.matchAll(/active: root\.want\("(\w+)"\)\s*\n\s*(\w+) \{\}/g)];
if (want.length === 0)
    fail("shell.qml: no components found");
if (JSON.stringify(all) !== JSON.stringify(want))
    fail(`dev.qml's list "all" (${all.join(" ")}) is not shell.qml's components (${want.join(" ")})`);
if (JSON.stringify(loaders.map(m => m[1])) !== JSON.stringify(want) || loaders.some(m => m[1] !== m[2]))
    fail(`dev.qml's loaders (${loaders.map(m => m[1] + ":" + m[2]).join(" ")}) are not one per shell.qml component, in order`);
else
    console.log(`ok   dev.qml loads shell.qml's ${want.length} components`);

console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
