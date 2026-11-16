import QtQuick
import Quickshell
import Quickshell.Io

// The shell's side of the lock screen (lock.qml runs as its own process).
//   qs ipc call lockscreen lock        start the lock screen
//   qs ipc call lockscreen hold <pid>  called by the lock process once the
//                                      compositor holds the lock; returns the
//                                      number of notifications waiting
// Notifications stay held until that process exits, however it exits.
//
// Before sleep: a logind delay inhibitor is held at all times; when logind
// announces sleep, the lock screen is started and the inhibitor released once
// the lock is up, so the machine wakes locked. logind waits at most
// InhibitDelayMaxSec (5 s by default) for that.
Scope {
    id: root

    property bool sleepPending: false

    function pushWaiting(): void {
        if (persist.pid !== 0)
            Quickshell.execDetached(["qs", "ipc", "--pid", String(persist.pid), "call", "lock", "setWaiting", String(LockState.waiting)]);
    }

    PersistentProperties {
        id: persist

        reloadableId: "lockscreen"

        onLoaded: if (pid !== 0)
            watch.start()

        // The lock process holding the session, or 0.
        property int pid: 0
    }

    Binding {
        target: LockState
        property: "held"
        value: persist.pid !== 0
    }

    Connections {
        target: LockState

        function onWaitingChanged() {
            root.pushWaiting();
        }
    }

    IpcHandler {
        target: "lockscreen"

        function lock(): void {
            LockState.lock();
        }
        function hold(pid: int): int {
            console.info("lock: held by", pid);
            persist.pid = pid;
            watch.start();
            return LockState.waiting;
        }
    }

    // Exits when the lock process does. Started by hand, not bound to
    // persist.pid, so the command never runs with a stale pid.
    Process {
        id: watch

        function start(): void {
            if (running)
                return;
            command = ["tail", "--pid=" + persist.pid, "-f", "/dev/null"];
            running = true;
        }

        onExited: {
            console.info("lock: released");
            persist.pid = 0;
        }
    }

    // `cat` keeps the inhibitor open until its stdin closes, which happens
    // with this Process however the shell stops, so no child is left behind.
    Process {
        running: !(root.sleepPending && LockState.held)
        stdinEnabled: true
        command: ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=Desktop shell", "--why=Locks the screen first", "cat"]
    }

    Process {
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        stdout: SplitParser {
            onRead: line => {
                const sleep = line.match(/\.PrepareForSleep \((true|false),\)/);
                if (!sleep)
                    return;
                root.sleepPending = sleep[1] === "true";
                console.info("lock: PrepareForSleep", sleep[1]);
                if (root.sleepPending && !LockState.held)
                    LockState.lock();
            }
        }
    }
}
