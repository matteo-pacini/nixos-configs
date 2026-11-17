// The shared notification sender (quickshell/common/notify.js): every text
// argument must reach the notification server as the string it was given.
// Run: node test-common.js <directory holding notify.js>
//
// gdbus reads each argument of `call` as GVariant text of the method's
// introspected type (or of any type, when introspection gave none), and only
// if that fails wraps it in double quotes, escaping nothing but `"`, and
// reads it again (glib 2.90 gio/gdbus-tool.c, the argument loop of `call` and
// _g_variant_parse_me_harder). `reads` below does the same, with a reader for
// the part of the GVariant text format these arguments can hit: a string
// literal (glib/gvariant-parser.c, token_stream_prepare and string_parse),
// and, untyped, a boolean or a number.
const assert = require("node:assert/strict");
const path = require("node:path");
const N = require(path.join(path.resolve(process.argv[2]), "notify.js"));
let n = 0;
const t = (name, f) => {
    try {
        f();
    } catch (e) {
        console.error(`not ok: ${name}`);
        throw e;
    }
    n++;
};

const SPACE = /^[ \t\n\v\f\r]+|[ \t\n\v\f\r]+$/g;
const ESCAPES = { a: "\x07", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t", v: "\v" };

// One string literal and nothing after it: { value } or { error }; null when
// the text does not start with a quote.
function literal(text) {
    const quote = text[0];
    if (quote !== "'" && quote !== '"')
        return null;
    let end = 1;
    for (; end < text.length && text[end] !== quote; end++)
        if (text[end] === "\\")
            end++;
    if (end >= text.length)
        return { error: "unterminated string constant" };
    if (text.slice(end + 1) !== "")
        return { error: "expected end of input" };
    let out = "";
    for (let i = 1; i < end;) {
        if (text[i] !== "\\") {
            out += text[i++];
            continue;
        }
        const e = text[++i];
        if (e === "u" || e === "U") {
            const hex = text.substr(i + 1, e === "u" ? 4 : 8);
            if (!/^[0-9a-fA-F]+$/.test(hex) || hex.length !== (e === "u" ? 4 : 8) || parseInt(hex, 16) === 0)
                return { error: "invalid unicode escape" };
            out += String.fromCodePoint(parseInt(hex, 16));
            i += 1 + hex.length;
        } else if (e in ESCAPES) {
            out += ESCAPES[e];
            i++;
        } else if (e === "\n") {
            i++;
        } else {
            out += e;
            i++;
        }
    }
    return { value: out };
}

// g_variant_parse of `text` as type `s`, or untyped (`typed` false).
function parse(text, typed) {
    const s = text.replace(SPACE, "");
    const lit = literal(s);
    if (lit)
        return lit;
    if (!typed && (s === "true" || s === "false"))
        return { value: s === "true" };
    if (!typed && /^[+-]?\d+(\.\d+)?$/.test(s))
        return { value: Number(s) };
    return { error: "not a string" };
}

// What the server receives for one argument, as gdbus reads it.
function reads(arg, typed) {
    const first = parse(arg, typed);
    if (!first.error)
        return first;
    return parse('"' + arg.replace(/"/g, '\\"') + '"', typed);
}

const NAMES = [
    ["plain", "Desk speaker"],
    ["single quotes", "Bob's phone"],
    ["double quotes", 'The "big" one'],
    ["a backslash", "C:\\speakers"],
    ["a trailing backslash", "back\\"],
    ["\\n as two characters", "line\\none"],
    ["a bad \\u escape", "tag\\u12"],
    ["a real newline", "two\nlines"],
    ["a quoted literal", "'Desk'"],
    ["a double-quoted literal", '"Desk"'],
    ["a boolean literal", "true"],
    ["a number literal", "42"],
    ["surrounding spaces", "  Desk  "],
    ["an empty string", ""],
    ["a quote and a backslash before it", 'say \\"hi\\"']
];

const SLOTS = { app: 9, icon: 11, summary: 12, body: 13 };

for (const [what, name] of NAMES) {
    t(`${what} arrives unchanged in every text argument`, () => {
        const cmd = N.command(name, 0, name, name, name, "[]", "{}", "int32 -1");
        for (const [slot, i] of Object.entries(SLOTS))
            for (const typed of [true, false])
                assert.deepEqual(reads(cmd[i], typed), { value: name }, `${slot}, ${typed ? "typed s" : "untyped"}: ${JSON.stringify(cmd[i])}`);
    });
}

t("the call, the id and the GVariant arguments as given", () => {
    const cmd = N.command("Calendar", 7, "x-office-calendar", "S", "B", "['open', 'Open']", "{'urgency': <byte 1>}", "int32 0");
    assert.deepEqual(cmd.slice(0, 9), ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify"]);
    assert.equal(cmd[10], "uint32 7");
    assert.deepEqual(cmd.slice(14), ["['open', 'Open']", "{'urgency': <byte 1>}", "int32 0"]);
    assert.equal(cmd.length, 17);
});

console.log(`ok: ${n} tests`);
