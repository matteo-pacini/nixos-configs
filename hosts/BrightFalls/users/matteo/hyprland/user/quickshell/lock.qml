import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.lock

// The lock screen. Its own Quickshell process, separate from the shell so
// that a reload or crash of the shell cannot unlock anything. Started by
// LockState.command, it locks every monitor through ext-session-lock, checks
// the password with PAM, unlocks and exits. If it exits any other way,
// Hyprland keeps the session locked and shows its own "lock screen died"
// screen; the README's "Lock screen" section has the recovery.
//
// While the compositor holds the lock it tells the shell (Lockscreen.qml),
// which holds notifications back until this process is gone and sends the
// number waiting:
//   qs ipc --pid <this> call lock setWaiting <n>
//
// DESK_LOCK_PREVIEW=1 shows the same faces as an overlay on DP-2 instead,
// with no session lock and no keyboard; the IpcHandler's preview functions
// drive it.
ShellRoot {
    id: root

    // Files are not watched: a reload while locked would throw away what was
    // typed.
    settings.watchFiles: false

    readonly property bool preview: Quickshell.env("DESK_LOCK_PREVIEW") === "1"
    // The PAM service in /etc/pam.d.
    readonly property string pamService: "desk-lock"

    readonly property date now: clock.date

    // The main monitor, which has the password field: picked once, when the
    // lock starts, so a monitor plugged in later shows only the clock.
    property string mainScreen: ""
    // Where the field is now: the main monitor, or the first one left while
    // the main one is gone.
    readonly property string fieldScreen: {
        const names = Array.from(Quickshell.screens).map(s => s.name);
        return names.includes(mainScreen) ? mainScreen : names[0] ?? "";
    }

    property string buffer: ""
    readonly property int length: buffer.length
    // idle, checking, wrong, heldoff or unlocking.
    property string phase: "idle"
    readonly property string fieldState: phase === "idle" ? (buffer === "" ? "waiting" : "typing") : phase
    property int failures: 0
    property bool capsLock: false
    // The last message PAM sent that was not a prompt, such as a lockout
    // notice from a module.
    property string systemMessage: ""
    property string heldReason: ""
    property int waiting: 0

    readonly property string note: {
        if (phase === "heldoff")
            return heldReason;
        if (capsLock && phase !== "unlocking")
            return "Caps Lock is on";
        if (failures > 0 && phase !== "unlocking")
            return failures === 1 ? "1 failed attempt" : failures + " failed attempts";
        return "";
    }
    readonly property string noteTone: phase === "heldoff" || (capsLock && phase !== "unlocking") ? "orange" : "red"

    // Preview only: which monitor shows it, and in which role.
    property bool previewShown: false
    property bool previewMain: true

    // Preview only: plays the faces' entrance again.
    signal replay

    // The monitor at the layout's origin (DP-1 at 0x0 in hypr/monitors.lua),
    // else the first one Quickshell lists.
    function pickMain(): string {
        const screens = Array.from(Quickshell.screens);
        return (screens.find(s => s.x === 0 && s.y === 0) ?? screens[0])?.name ?? "";
    }

    function key(event): void {
        const mods = event.modifiers & ~Qt.KeypadModifier;
        event.accepted = true;
        if (event.key === Qt.Key_CapsLock) {
            capsDelay.restart();
            return;
        }
        if (phase === "checking" || phase === "unlocking")
            return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            submit();
            return;
        }
        if (event.key === Qt.Key_Escape)
            buffer = "";
        else if (event.key === Qt.Key_Backspace)
            buffer = buffer.slice(0, -1);
        else if (event.text !== "" && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && !(mods & Qt.ControlModifier))
            buffer += event.text;
        else {
            event.accepted = false;
            return;
        }
        phase = "idle";
    }

    function submit(): void {
        if (buffer === "" || phase === "checking" || phase === "unlocking")
            return;
        phase = "checking";
        systemMessage = "";
        if (!pam.start()) {
            buffer = "";
            holdOff("could not start the password check");
        }
    }

    function holdOff(reason: string): void {
        heldReason = reason;
        phase = "heldoff";
    }

    function unlock(): void {
        phase = "unlocking";
        if (!preview)
            lock.locked = false;
    }

    Component.onCompleted: {
        mainScreen = pickMain();
        if (!preview)
            capsCheck.running = true;
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    WlSessionLock {
        id: lock

        locked: !root.preview

        // `secure` drops when the lock ends: unlocked here, or refused or
        // ended by the compositor. Quickshell 0.3.2 does not signal `locked`
        // going false after its own unlock, so this is the exit.
        onSecureChanged: {
            if (secure)
                announce.running = true;
            else
                quit.start();
        }

        WlSessionLockSurface {
            id: surface

            // The colour Hyprland paints before the first frame; LockFace
            // fades from it.
            color: "black"

            LockFace {
                anchors.fill: parent
                lock: root
                main: surface.screen?.name === root.fieldScreen
            }
        }
    }

    // Lets the unlock reach the compositor before the connection closes; a
    // client that disconnects still holding the lock leaves the session
    // locked.
    Timer {
        id: quit

        interval: 500
        onTriggered: Qt.quit()
    }

    PamContext {
        id: pam

        config: root.pamService

        onPamMessage: {
            if (responseRequired && !responseVisible) {
                respond(root.buffer);
                root.buffer = "";
            } else if (responseRequired) {
                // A visible prompt (a user name, a code) is nothing this
                // screen can answer.
                root.systemMessage = message;
                abort();
            } else if (message !== "") {
                root.systemMessage = message;
            }
        }
        onCompleted: result => {
            root.buffer = "";
            if (result === PamResult.Success) {
                root.unlock();
                return;
            }
            if (result === PamResult.Error) {
                root.holdOff("the system could not check the password");
                return;
            }
            root.failures++;
            if (result === PamResult.MaxTries || (root.systemMessage !== "" && pam.messageIsError))
                root.holdOff("too many failed attempts");
            else
                root.phase = "wrong";
        }
        onError: error => console.warn("lock: PAM error:", PamError.toString(error))
    }

    Timer {
        id: capsDelay

        // Hyprland updates its keyboard state after passing the key on.
        interval: 80
        onTriggered: capsCheck.running = true
    }

    Process {
        id: capsCheck

        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.capsLock = JSON.parse(text).keyboards.some(k => k.main && k.capsLock);
                } catch (e) {
                    console.warn("lock: cannot read the Caps Lock state:", e.message);
                }
            }
        }
    }

    // Tells the shell the session is locked; it answers with the number of
    // notifications waiting.
    Process {
        id: announce

        command: ["qs", "ipc", "call", "lockscreen", "hold", String(Quickshell.processId)]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text);
                if (!isNaN(n))
                    root.waiting = n;
            }
        }
    }

    IpcHandler {
        target: "lock"

        function setWaiting(count: int): void {
            root.waiting = count;
        }

        // Preview only, from here on.
        function reveal(shown: bool): void {
            if (!root.preview)
                return;
            root.previewShown = shown;
            if (shown)
                root.replay();
        }
        function role(main: bool): void {
            if (root.preview)
                root.previewMain = main;
        }
        function type(text: string): void {
            if (!root.preview || root.phase === "checking")
                return;
            root.buffer += text;
            root.phase = "idle";
        }
        function press(name: string): void {
            if (!root.preview)
                return;
            if (name === "enter")
                root.submit();
            else if (name === "escape")
                root.buffer = "";
            else if (name === "backspace")
                root.buffer = root.buffer.slice(0, -1);
        }
        function caps(on: bool): void {
            if (root.preview)
                root.capsLock = on;
        }
        function holdOff(message: string): void {
            if (!root.preview)
                return;
            root.systemMessage = message;
            root.holdOff("too many failed attempts");
        }
        function setFailures(count: int): void {
            if (root.preview)
                root.failures = count;
        }
        function setPhase(phase: string): void {
            if (root.preview)
                root.phase = phase;
        }
    }

    PanelWindow {
        visible: root.preview && root.previewShown
        screen: Array.from(Quickshell.screens).find(s => s.name === "DP-2") ?? Quickshell.screens[0]
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "desk-lock-preview"

        LockFace {
            anchors.fill: parent
            lock: root
            main: root.previewMain
        }
    }
}
