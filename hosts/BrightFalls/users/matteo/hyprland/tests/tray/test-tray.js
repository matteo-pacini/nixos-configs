// The tray menu's library (quickshell/tray/menu.js) against invented items,
// with the button types' values from the installed Quickshell's type file.
// Run: node test-tray.js <directory holding menu.js> <Quickshell/quickshell-core.qmltypes>
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const M = require(path.join(path.resolve(process.argv[2]), "menu.js"));
// QsMenuButtonType's names in value order. The values are implicit in the
// type file, so this relies on qsmenu.hpp numbering them from 0 without gaps
// (true in 0.3.2).
const BUTTON_TYPES = (() => {
    const block = fs.readFileSync(process.argv[3], "utf8").split("Component {")
        .find(b => b.includes('name: "qs::menu::QsMenuButtonType"'));
    return JSON.parse(`[${block.match(/values: \[([^\]]*)\]/)[1]}]`);
})();
const [NONE, CHECKBOX, RADIO] = ["None", "CheckBox", "RadioButton"].map(name => {
    assert.ok(BUTTON_TYPES.includes(name), `QsMenuButtonType has no ${name}`);
    return BUTTON_TYPES.indexOf(name);
});
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

t("the tooltip's name wins over a class-like title and id", () => {
    assert.equal(M.title("Chat Desktop", "ChatDesktop", "ChatDesktop"), "Chat Desktop");
});

t("an unread count after the name is dropped", () => {
    assert.equal(M.title("Chat Desktop (3)", "ChatDesktop", "x"), "Chat Desktop");
    assert.equal(M.title("Chat Desktop (120) ", "", ""), "Chat Desktop");
});

t("brackets that are not a count stay", () => {
    assert.equal(M.title("Sync (paused)", "", ""), "Sync (paused)");
});

t("falls back to the title, then the id, skipping blanks", () => {
    assert.equal(M.title("", "Dictation", "dict"), "Dictation");
    assert.equal(M.title("  ", undefined, "dict"), "dict");
    assert.equal(M.title(null, null, null), "");
});

t("a count alone is no name", () => {
    assert.equal(M.title("(3)", "Title", "id"), "Title");
});

t("checkbox marks", () => {
    assert.deepEqual(M.mark(CHECKBOX, 2), { text: "✓", on: true });
    assert.deepEqual(M.mark(CHECKBOX, 0), { text: "☐", on: false });
    assert.deepEqual(M.mark(CHECKBOX, 1), { text: "▣", on: false });
});

t("radio marks", () => {
    assert.deepEqual(M.mark(RADIO, 2), { text: "●", on: true });
    assert.deepEqual(M.mark(RADIO, 0), { text: "○", on: false });
    // A radio has no partial state; it reads as not chosen.
    assert.deepEqual(M.mark(RADIO, 1), { text: "○", on: false });
});

t("plain entries have no mark, whatever their check state", () => {
    assert.deepEqual(M.mark(NONE, 0), { text: "", on: false });
    assert.deepEqual(M.mark(NONE, 2), { text: "", on: false });
});

console.log(`ok: ${n} tests`);
