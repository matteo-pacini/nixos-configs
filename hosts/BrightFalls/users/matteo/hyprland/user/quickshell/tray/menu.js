// The tray menu's decisions: the name in its header and the mark beside an
// entry. Plain JavaScript so node can run it too.

// QsMenuButtonType and Qt.CheckState, by value.
const CHECKBOX = 1;
const RADIO = 2;
const PARTIAL = 1;
const CHECKED = 2;

// The application's name for the menu's header, from a SystemTrayItem's
// tooltipTitle, title and id, the first that is not empty. The tooltip comes
// first: it is the only one written for people (an id or title such as
// "TelegramDesktop" is often a class name). A trailing count in brackets,
// "Telegram Desktop (3)", is unread items, not part of the name.
function title(tooltipTitle, itemTitle, id) {
    for (const s of [tooltipTitle, itemTitle, id]) {
        const name = (s ?? "").replace(/\s*\(\d+\)\s*$/, "").trim();
        if (name !== "")
            return name;
    }
    return "";
}

// The mark beside an entry: { text, on }, text "" for none. `on` marks a
// checked box or the chosen radio, drawn green.
function mark(buttonType, checkState) {
    if (buttonType === CHECKBOX)
        return checkState === CHECKED ? { text: "✓", on: true } : { text: checkState === PARTIAL ? "▣" : "☐", on: false };
    if (buttonType === RADIO)
        return checkState === CHECKED ? { text: "●", on: true } : { text: "○", on: false };
    return { text: "", on: false };
}

if (typeof module !== "undefined")
    module.exports = { title, mark };
