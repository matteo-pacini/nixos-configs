// The tray menu's library (quickshell/tray/menu.js) against invented items.
// Run: node test-tray.js <directory holding menu.js>
const assert = require("node:assert/strict");
const path = require("node:path");
const M = require(path.join(path.resolve(process.argv[2]), "menu.js"));
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
    assert.deepEqual(M.mark(1, 2), { text: "✓", on: true });
    assert.deepEqual(M.mark(1, 0), { text: "☐", on: false });
    assert.deepEqual(M.mark(1, 1), { text: "▣", on: false });
});

t("radio marks", () => {
    assert.deepEqual(M.mark(2, 2), { text: "●", on: true });
    assert.deepEqual(M.mark(2, 0), { text: "○", on: false });
});

t("plain entries have no mark, whatever their check state", () => {
    assert.deepEqual(M.mark(0, 0), { text: "", on: false });
    assert.deepEqual(M.mark(0, 2), { text: "", on: false });
});

console.log(`ok: ${n} tests`);
