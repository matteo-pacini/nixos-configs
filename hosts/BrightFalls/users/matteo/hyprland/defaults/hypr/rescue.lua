-- Loaded last by hyprland.lua so a terminal, reload and exit survive any
-- error in bindings.lua. Each key is unbound first because Hyprland runs
-- every bind on a key: a copy of one of these elsewhere would fire twice.
-- Descriptions follow bindings.lua's "<group>: <description>" form for the
-- cheat sheet; this file has its own helper so it does not depend on that one.

local function rescue(group, keys, description, dispatcher)
    hl.unbind(keys)
    hl.bind(keys, dispatcher, { description = group .. ": " .. description })
end

rescue("Apps", "SUPER + RETURN", "Terminal", hl.dsp.exec_cmd("uwsm app -- ghostty"))
rescue("Session", "SUPER + SHIFT + R", "Reload config", hl.dsp.reload_config())
-- UWSM stops the session's units in order; exiting Hyprland directly would
-- pull the compositor out from under them.
rescue("Session", "SUPER + SHIFT + ESCAPE", "Exit session", hl.dsp.exec_cmd("uwsm stop"))
