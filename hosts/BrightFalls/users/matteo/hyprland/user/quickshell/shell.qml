// The desktop shell: one Quickshell process. Each component is a file in
// this directory and one line below. Quickshell reloads when a file here
// changes; see hosts/BrightFalls/users/matteo/hyprland/README.md in
// nixos-configs.

// Read at startup only, so a change needs a restart. Sets the icon theme
// here rather than leaving it to Qt's platform theme, whose answer depends on
// the environment the service starts with.
//@ pragma IconTheme Adwaita

import Quickshell
import Quickshell.Io
import qs.calendar
import qs.tray

ShellRoot {
    // Called by `desk-sync activate` once a switch has written every file.
    // The answer is how the caller knows the call ran: `qs ipc call` exits 0
    // even when the shell refused it.
    IpcHandler {
        target: "shell"

        function reload(): string {
            Quickshell.reload(false);
            return "reloaded";
        }
    }

    Launcher {}
    Bar {}
    Notifications {}
    Osd {}
    Cheatsheet {}
    SessionMenu {}
    Polkit {}
    Network {}
    Audio {}
    Calendar {}
    CalendarFull {}
    System {}
    BluetoothPanel {}
    Office {}
    Fleet {}
    Tailscale {}
    Tokens {}
    Weather {}
    TrayMenu {}
    Reminders {}
    Lockscreen {}
}
