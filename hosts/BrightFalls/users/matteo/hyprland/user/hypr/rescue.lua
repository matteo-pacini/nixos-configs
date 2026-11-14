-- Loaded last by hyprland.lua so a terminal, reload and exit survive any
-- error in bindings.lua. Each key is unbound first because Hyprland runs
-- every bind on a key: a copy of one of these elsewhere would fire twice.

local function rescue(keys, dispatcher)
    hl.unbind(keys)
    hl.bind(keys, dispatcher)
end

rescue("SUPER + RETURN", hl.dsp.exec_cmd("uwsm app -- ghostty"))
rescue("SUPER + SHIFT + R", hl.dsp.reload_config())
-- UWSM stops the session's units in order; exiting Hyprland directly would
-- pull the compositor out from under them.
rescue("SUPER + SHIFT + ESCAPE", hl.dsp.exec_cmd("uwsm stop"))
