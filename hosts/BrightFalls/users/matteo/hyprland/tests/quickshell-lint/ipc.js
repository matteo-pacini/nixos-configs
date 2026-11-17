// Every `qs ipc call <target> <function> <args>` in the given Lua files (the
// Hyprland binds) and in the shell's QML must name the target of an
// IpcHandler in the QML and a function of that handler taking as many
// arguments as the call passes. Every function of every handler must use
// only types Quickshell carries over IPC (src/io/ipc.cpp): one with any other
// type is dropped when the handler loads, with only a log line to show it.
// Usage: node ipc.js <quickshell directory> <lua file>...
"use strict";
const fs = require("fs");
const path = require("path");

const [root, ...luaFiles] = process.argv.slice(2);
const IPC_TYPES = new Set(["string", "int", "bool", "real", "double", "color"]);
const errors = [];

function qmlFiles(dir) {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name))
    .flatMap((e) => {
      const p = path.join(dir, e.name);
      return e.isDirectory() ? qmlFiles(p) : e.name.endsWith(".qml") ? [p] : [];
    });
}

// The text with comments, and with keepStrings false the inside of string
// literals too, replaced by spaces; newlines and offsets are kept, so braces
// and commas in them are not counted and line numbers still hold.
function blank(src, keepStrings) {
  let out = "";
  let i = 0;
  const space = (s) => s.replace(/[^\n]/g, " ");
  while (i < src.length) {
    const c = src[i];
    if (c === "/" && src[i + 1] === "/") {
      const end = src.indexOf("\n", i) < 0 ? src.length : src.indexOf("\n", i);
      out += space(src.slice(i, end));
      i = end;
    } else if (c === "/" && src[i + 1] === "*") {
      const end = src.indexOf("*/", i + 2) < 0 ? src.length : src.indexOf("*/", i + 2) + 2;
      out += space(src.slice(i, end));
      i = end;
    } else if (c === '"' || c === "'" || c === "`") {
      let j = i + 1;
      while (j < src.length && src[j] !== c) j += src[j] === "\\" ? 2 : 1;
      const inner = src.slice(i + 1, j);
      out += c + (keepStrings ? inner : space(inner)) + (j < src.length ? c : "");
      i = j + 1;
    } else {
      out += c;
      i++;
    }
  }
  return out;
}

const lineAt = (text, offset) => text.slice(0, offset).split("\n").length;

// The handlers: target -> { file, functions: name -> parameter count }.
const handlers = new Map();
const qml = qmlFiles(root).map((file) => {
  const src = fs.readFileSync(file, "utf8");
  return { file, rel: path.relative(root, file), src, bare: blank(src, false), code: blank(src, true) };
});
for (const { rel, src, bare } of qml) {
  for (const m of bare.matchAll(/\bIpcHandler\s*\{/g)) {
    const open = m.index + m[0].length - 1;
    // The handler's own level: nested blocks blanked out.
    let depth = 0;
    let end = open;
    let top = "";
    for (let i = open; i < bare.length; i++) {
      const c = bare[i];
      if (c === "{") depth++;
      if (c === "}") depth--;
      top += depth === 1 && c !== "{" ? c : c === "\n" ? "\n" : " ";
      if (depth === 0) {
        end = i;
        break;
      }
    }
    const where = `${rel}:${lineAt(src, open)}`;
    const t = /\btarget\s*:\s*"/.exec(top);
    if (!t) {
      errors.push(`${where}: an IpcHandler whose target is not a string literal; this check cannot follow it`);
      continue;
    }
    const q = open + t.index + t[0].length;
    const target = src.slice(q, src.indexOf('"', q));
    const functions = new Map();
    for (const f of top.matchAll(/\bfunction\s+(\w+)\s*\(([^)]*)\)\s*(?::\s*([\w<>.]+))?/g)) {
      const params = f[2]
        .split(",")
        .map((p) => p.trim())
        .filter(Boolean);
      const fwhere = `${rel}:${lineAt(src, open + f.index)}`;
      for (const p of params) {
        const type = p.split(":")[1]?.trim();
        if (!IPC_TYPES.has(type))
          errors.push(`${fwhere}: ${target}.${f[1]}: parameter "${p}" needs one of the types ${[...IPC_TYPES].join(", ")}; without it Quickshell drops the function`);
      }
      if (f[3] && f[3] !== "void" && f[3] !== "var" && !IPC_TYPES.has(f[3]))
        errors.push(`${fwhere}: ${target}.${f[1]}: return type ${f[3]} cannot be sent over IPC; Quickshell drops the function`);
      functions.set(f[1], params.length);
    }
    if (handlers.has(target))
      errors.push(`${where}: IpcHandler target "${target}" is also declared in ${handlers.get(target).file}`);
    handlers.set(target, { file: rel, functions });
  }
}

// The calls: from strings ("qs ipc call launcher toggle") and, in QML, from
// command arrays (["qs", "ipc", "--pid", pid, "call", "launcher", "toggle"]).
const calls = [];
const fromString = (where, text) => {
  for (const m of text.matchAll(/qs ipc (?:--pid \S+ )?call ([^"]*)"/g)) {
    const [target, fn, ...args] = m[1].trim().split(/\s+/);
    calls.push({ where: `${where(m.index)}`, text: `qs ipc call ${m[1].trim()}`, target, fn, args: args.length });
  }
};
for (const file of luaFiles) {
  const lines = fs.readFileSync(file, "utf8").split("\n");
  lines.forEach((line, i) => {
    if (!line.trim().startsWith("--")) fromString(() => `${path.basename(file)}:${i + 1}`, line.replace(/--[^"]*$/, ""));
  });
}
for (const { rel, src, code } of qml) {
  fromString((at) => `${rel}:${lineAt(src, at)}`, code);
  for (const m of code.matchAll(/\[\s*"qs"\s*,\s*"ipc"\s*,([^\]]*)\]/g)) {
    const where = `${rel}:${lineAt(src, m.index)}`;
    const items = [];
    let depth = 0;
    let item = "";
    for (const c of m[1]) {
      if (c === "(") depth++;
      if (c === ")") depth--;
      if (c === "," && depth === 0) {
        items.push(item.trim());
        item = "";
      } else item += c;
    }
    items.push(item.trim());
    if (items[0] === '"--pid"') items.splice(0, 2);
    const lit = (s) => /^"[^"]*"$/.exec(s ?? "")?.[0].slice(1, -1);
    if (lit(items[0]) !== "call") continue;
    const [target, fn] = [lit(items[1]), lit(items[2])];
    const text = `qs ipc call ${items.slice(1).map((s) => lit(s) ?? s).join(" ")}`;
    if (target === undefined || fn === undefined) {
      errors.push(`${where}: ${text}: target and function must be string literals for this check to follow them`);
      continue;
    }
    calls.push({ where, text, target, fn, args: items.length - 3 });
  }
}

for (const c of calls) {
  const h = handlers.get(c.target);
  if (!h) {
    errors.push(`${c.where}: ${c.text}: no IpcHandler has target "${c.target}" (targets: ${[...handlers.keys()].sort().join(", ")})`);
    continue;
  }
  if (!h.functions.has(c.fn)) {
    errors.push(`${c.where}: ${c.text}: IpcHandler "${c.target}" (${h.file}) has no function "${c.fn}" (functions: ${[...h.functions.keys()].join(", ")})`);
    continue;
  }
  const n = h.functions.get(c.fn);
  if (n !== c.args)
    errors.push(`${c.where}: ${c.text}: ${c.target}.${c.fn} (${h.file}) takes ${n} argument(s), the call passes ${c.args}`);
}
if (calls.length === 0) errors.push("no qs ipc call found at all: the patterns above no longer match how the calls are written");

for (const e of errors) console.log(`ipc: ${e}`);
if (errors.length) process.exit(1);
console.log(`ipc: ${calls.length} calls checked against ${handlers.size} IpcHandler targets`);
