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

local screenshot = "satty --filename - --output-filename '~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png'"
    .. " --copy-command wl-copy --early-exit"
bind("Capture and dictation", "Print", "Screenshot region", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | " .. screenshot))
bind("Capture and dictation", "SHIFT + Print", "Screenshot monitor", function()
    hl.dispatch(hl.dsp.exec_cmd("grim -o " .. hl.get_active_monitor().name .. " - | " .. screenshot))
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
