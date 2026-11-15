pragma Singleton

import QtQuick
import Quickshell

// Whether the lock screen (lock.qml, its own process) holds the session, as
// Lockscreen.qml learns it, and how to start it. While `held`, the shell
// keeps notifications and reminders back.
Singleton {
    // Set by Lockscreen.qml from the moment the compositor confirms the lock
    // until the lock process exits.
    property bool held: false
    // Notifications on screen or waiting to be, kept by Notifications.qml.
    property int waiting: 0

    // In its own transient unit, outside the shell's cgroup, so restarting
    // the shell cannot end it. The fixed unit name refuses a second lock.
    // The Super+L bind in hypr/bindings.lua runs the same command.
    readonly property list<string> command: ["systemd-run", "--user", "--unit=desk-lock", "--collect", "--quiet", "qs", "-n", "-p", Quickshell.shellPath("lock.qml")]

    function lock(): void {
        console.info("lock: starting the lock screen");
        Quickshell.execDetached(command);
    }
}
