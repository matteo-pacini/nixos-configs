// The command line that sends a desktop notification, shared by the shell's
// senders. Plain JavaScript so node can run it too.

// GVariant text for a string. gdbus reads each argument as GVariant text
// first, so an unquoted name such as 'Desk' or one with a backslash would
// arrive altered, or not at all.
function gv(s) {
    return "'" + s.replace(/\\/g, "\\\\").replace(/'/g, "\\'").replace(/\n/g, "\\n") + "'";
}

// `gdbus call` to org.freedesktop.Notifications.Notify. `app`, `icon`,
// `summary` and `body` are plain text; `replaces` is a notification id, 0
// for a new one; `actions`, `hints` and `timeout` are GVariant text as gdbus
// reads it, such as "['open', 'Open']", "{'urgency': <byte 2>}" and
// "int32 -1" (a bare -1 is read as an option).
function command(app, replaces, icon, summary, body, actions, hints, timeout) {
    return ["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify", gv(app), "uint32 " + replaces, gv(icon), gv(summary), gv(body), actions, hints, timeout];
}

if (typeof module !== "undefined")
    module.exports = { command };
