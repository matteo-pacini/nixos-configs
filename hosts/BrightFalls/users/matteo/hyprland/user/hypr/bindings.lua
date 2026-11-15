-- Keybindings, after Omarchy's default/hypr/bindings. Super+K lists them
-- (quickshell/Cheatsheet.qml), from the descriptions given here.

-- Binds `keys` with Hyprland's description "<group>: <description>", which
-- the cheat sheet splits back into a group heading and a row. Groups appear
-- on the sheet in the order of their first bind; binds that share a
-- description share a row. `opts` are hl.bind's options.
local function bind(group, keys, description, dispatcher, opts)
    opts = opts or {}
    opts.description = group .. ": " .. description
    return hl.bind(keys, dispatcher, opts)
end

local function launch(cmd)
    return hl.dsp.exec_cmd("uwsm app -- " .. cmd)
end

-- Super+Return (terminal), Super+Shift+R (reload) and Super+Shift+Escape
-- (exit) are in rescue.lua.
bind("Apps", "SUPER + SPACE", "App launcher", hl.dsp.exec_cmd("qs ipc call launcher toggle"))
bind("Apps", "SUPER + CTRL + RETURN", "Herdr", launch("herdr-app"))
bind("Apps", "SUPER + SHIFT + B", "Firefox", launch("firefox"))
bind("Apps", "SUPER + SHIFT + S", "Steam", launch("steam"))

bind("Windows", "SUPER + W", "Close window", hl.dsp.window.close())
bind("Windows", "SUPER + F", "Fullscreen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
bind("Windows", "SUPER + T", "Toggle floating", hl.dsp.window.float({ action = "toggle" }))
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    bind("Windows", "SUPER + " .. dir, "Move focus", hl.dsp.focus({ direction = dir }))
end
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    bind("Windows", "SUPER + SHIFT + " .. dir, "Swap window", hl.dsp.window.swap({ direction = dir }))
end
bind("Windows", "SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
bind("Windows", "SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

-- Workspaces 1-5 are on DP-1, 6-10 on DP-2 (monitors.lua).
for i = 1, 10 do
    bind("Workspaces", "SUPER + " .. i % 10, "Go to workspace 1 to 10", hl.dsp.focus({ workspace = i }))
end
for i = 1, 10 do
    bind("Workspaces", "SUPER + SHIFT + " .. i % 10, "Move window to workspace", hl.dsp.window.move({ workspace = i }))
end

bind("Audio and media", "SUPER + SHIFT + O", "Cycle audio output", hl.dsp.exec_cmd("audio-output-cycle"))
bind("Audio and media", "XF86AudioRaiseVolume", "Volume up / down",
    hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
bind("Audio and media", "XF86AudioLowerVolume", "Volume up / down",
    hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
bind("Audio and media", "XF86AudioMute", "Mute output / microphone",
    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
bind("Audio and media", "XF86AudioMicMute", "Mute output / microphone",
    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
bind("Audio and media", "XF86AudioPlay", "Play, next, previous", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("Audio and media", "XF86AudioPause", "Play, next, previous", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("Audio and media", "XF86AudioNext", "Play, next, previous", hl.dsp.exec_cmd("playerctl next"), { locked = true })
bind("Audio and media", "XF86AudioPrev", "Play, next, previous", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

local slurped = "g=$(slurp) && "
local notifySaved = "busctl --user --quiet call org.freedesktop.Notifications /org/freedesktop/Notifications"
    .. " org.freedesktop.Notifications Notify 'susssasa{sv}i' Screenshot 0 '' Screenshot 'Saved and copied' 0 0 3000"
local function saveAndCopy(grimArgs)
    return "f=\"$HOME/Pictures/Screenshots/Screenshot from $(date '+%Y-%m-%d %H-%M-%S').png\" && grim " .. grimArgs
        .. " \"$f\" && wl-copy --type image/png < \"$f\" && " .. notifySaved
end
-- In Satty, Enter, Ctrl+C and the copy button copy, save and close; Ctrl+S
-- only saves and keeps it open.
local satty = "satty --filename - --output-filename '~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png'"
    .. " --copy-command wl-copy --save-after-copy --early-exit copy --actions-on-enter save-to-clipboard"
bind("Capture and dictation", "Print", "Screenshot region", hl.dsp.exec_cmd(slurped .. saveAndCopy("-g \"$g\"")))
bind("Capture and dictation", "SHIFT + Print", "Screenshot monitor", function()
    hl.dispatch(hl.dsp.exec_cmd(saveAndCopy("-o " .. hl.get_active_monitor().name)))
end)
bind("Capture and dictation", "SUPER + Print", "Edit region in Satty",
    hl.dsp.exec_cmd(slurped .. "grim -g \"$g\" - | " .. satty))
bind("Capture and dictation", "SUPER + SHIFT + Print", "Edit monitor in Satty", function()
    hl.dispatch(hl.dsp.exec_cmd("grim -o " .. hl.get_active_monitor().name .. " - | " .. satty))
end)
-- Hyprland gives the portal shortcuts Hex registers no key, so these run
-- Hex's commands instead. Toggle matches Hex's shortcut_mode setting.
bind("Capture and dictation", "CTRL + ALT + SPACE", "Dictate", hl.dsp.exec_cmd("hex dictation toggle"))
bind("Capture and dictation", "CTRL + ALT + V", "Paste last dictation", hl.dsp.exec_cmd("hex paste-last"))

bind("Notifications", "SUPER + COMMA", "Dismiss newest", hl.dsp.exec_cmd("qs ipc call notifications dismissNewest"))
bind("Notifications", "SUPER + SHIFT + COMMA", "Dismiss all", hl.dsp.exec_cmd("qs ipc call notifications dismissAll"))
-- Critical notifications still show.
bind("Notifications", "SUPER + CTRL + COMMA", "Do not disturb", hl.dsp.exec_cmd("qs ipc call notifications toggleDnd"))

-- DP-2 off, no animations or blur; again to undo. Turning it off reloads the
-- config, which brings back DP-2, animations and blur from the other files
-- and resets this flag with the rest of Lua state.
local gameMode = false
bind("Session", "SUPER + CTRL + G", "Game mode", function()
    if gameMode then
        hl.dispatch(hl.dsp.reload_config())
        return
    end
    gameMode = true
    hl.monitor({ output = "DP-2", disabled = true })
    hl.config({ animations = { enabled = false }, decoration = { blur = { enabled = false } } })
end)
bind("Session", "SUPER + K", "Keybindings", hl.dsp.exec_cmd("qs ipc call cheatsheet toggle"))
bind("Session", "SUPER + ESCAPE", "Session menu", hl.dsp.exec_cmd("qs ipc call session toggle"))
-- The command in quickshell/LockState.qml, run here directly so the key locks
-- even while the shell is down.
local config = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
bind("Session", "SUPER + L", "Lock", hl.dsp.exec_cmd("systemd-run --user --unit=desk-lock --collect --quiet qs -n -p "
    .. config .. "/quickshell/lock.qml"))
bind("Session", "SUPER + N", "Network", hl.dsp.exec_cmd("qs ipc call network toggle"))
bind("Session", "SUPER + A", "Audio", hl.dsp.exec_cmd("qs ipc call audio toggle"))
bind("Session", "SUPER + C", "Calendar", hl.dsp.exec_cmd("qs ipc call calendar toggle"))
bind("Session", "SUPER + Y", "System", hl.dsp.exec_cmd("qs ipc call system toggle"))
bind("Session", "SUPER + B", "Bluetooth", hl.dsp.exec_cmd("qs ipc call bluetooth toggle"))
-- Super+Shift+B is Firefox.
bind("Session", "SUPER + CTRL + B", "Bluetooth on/off", hl.dsp.exec_cmd("qs ipc call bluetooth power"))
-- logind must ignore a short press (HandlePowerKey in desktop-hyprland.nix),
-- or it powers off before the menu shows.
bind("Session", "XF86PowerOff", "Session menu", hl.dsp.exec_cmd("qs ipc call session toggle"))
