-- Keybindings, after Omarchy's default/hypr/bindings. There is no launcher or
-- help overlay yet, so this is the list:
--
--   Super+Return              terminal (ghostty)              [rescue.lua]
--   Super+Shift+R             reload config                   [rescue.lua]
--   Super+Shift+Escape        exit the session                [rescue.lua]
--
--   Super+Ctrl+Return         Herdr desktop app
--   Super+Shift+B             Firefox
--   Super+Shift+S             Steam
--
--   Super+W                   close window
--   Super+F                   fullscreen
--   Super+T                   toggle floating
--   Super+Left/Right/Up/Down  move focus
--   Super+Shift+arrows        swap window in that direction
--   Super+1..9                go to workspace
--   Super+Shift+1..9          move window to workspace
--   Super+drag left/right     move / resize window
--
--   Super+Shift+O             cycle audio output
--   Super+Ctrl+G              game mode: DP-2 off, no animations or blur; again to undo
--   Print                     screenshot a region, annotate in satty
--   Shift+Print               screenshot the focused monitor, annotate in satty
--   Ctrl+Alt+Space            Hex dictation (start, then stop and paste)
--   Ctrl+Alt+V                Hex: paste the last dictation again
--   Volume, mute and media keys

local function launch(cmd)
    return hl.dsp.exec_cmd("uwsm app -- " .. cmd)
end

hl.bind("SUPER + CTRL + RETURN", launch("herdr-app"))
hl.bind("SUPER + SHIFT + B", launch("firefox"))
hl.bind("SUPER + SHIFT + S", launch("steam"))

hl.bind("SUPER + W", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind("SUPER + T", hl.dsp.window.float({ action = "toggle" }))

for _, dir in ipairs({ "left", "right", "up", "down" }) do
    hl.bind("SUPER + " .. dir, hl.dsp.focus({ direction = dir }))
    hl.bind("SUPER + SHIFT + " .. dir, hl.dsp.window.swap({ direction = dir }))
end

for i = 1, 9 do
    hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind("SUPER + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd("audio-output-cycle"))

-- Turning it off reloads the config, which brings back DP-2, animations and
-- blur from the other files and resets this flag with the rest of Lua state.
local gameMode = false
hl.bind("SUPER + CTRL + G", function()
    if gameMode then
        hl.dispatch(hl.dsp.reload_config())
        return
    end
    gameMode = true
    hl.monitor({ output = "DP-2", disabled = true })
    hl.config({ animations = { enabled = false }, decoration = { blur = { enabled = false } } })
end)

local screenshot = "satty --filename - --output-filename '~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png'"
    .. " --copy-command wl-copy --early-exit"
hl.bind("Print", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | " .. screenshot))
hl.bind("SHIFT + Print", function()
    hl.dispatch(hl.dsp.exec_cmd("grim -o " .. hl.get_active_monitor().name .. " - | " .. screenshot))
end)

-- Hyprland gives the portal shortcuts Hex registers no key, so these run
-- Hex's commands instead. Toggle matches Hex's shortcut_mode setting.
hl.bind("CTRL + ALT + SPACE", hl.dsp.exec_cmd("hex dictation toggle"))
hl.bind("CTRL + ALT + V", hl.dsp.exec_cmd("hex paste-last"))

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
