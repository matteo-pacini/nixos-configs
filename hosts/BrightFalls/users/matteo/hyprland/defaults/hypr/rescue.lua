-- Loaded last by hyprland.lua so a terminal, reload and exit survive any
-- error in bindings.lua. Each key is unbound first because Hyprland runs
-- every bind on a key: a copy of one of these elsewhere would fire twice.
-- Descriptions follow bindings.lua's "<group>: <description>" form for the
-- cheat sheet; this file has its own helper so it does not depend on that one.

local function rescue(group, keys, description, dispatcher, opts)
    opts = opts or {}
    opts.description = group .. ": " .. description
    hl.unbind(keys)
    hl.bind(keys, dispatcher, opts)
end

rescue("Apps", "SUPER + RETURN", "Terminal", hl.dsp.exec_cmd("uwsm app -- ghostty"))
rescue("Session", "SUPER + SHIFT + R", "Reload config", hl.dsp.reload_config())
-- UWSM stops the session's units in order; exiting Hyprland directly would
-- pull the compositor out from under them.
rescue("Session", "SUPER + SHIFT + ESCAPE", "Exit session", hl.dsp.exec_cmd("uwsm stop"))
-- DP-1 and DP-2 back as declared if single-monitor left DP-2 off
-- (hosts/BrightFalls/display-layout.sh). Works while locked too, since the
-- lock may be on a monitor nobody can see.
rescue("Session", "SUPER + SHIFT + D", "Restore monitors", hl.dsp.exec_cmd("display-layout restore"),
    { locked = true })
