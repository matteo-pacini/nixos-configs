-- Hyprland 0.57 config entry point.
--
-- Hyprland's require() runs each file in its own scope: an error in one file
-- is listed by `hyprctl configerrors` and the remaining files still load. Only
-- a missing file aborts this one, so every name below must exist. A reload
-- clears package.loaded, so edited files are read again.

require("monitors")
require("input")
require("looknfeel")
require("rules")
require("bindings")
require("autostart")

-- Last, so it rebinds its keys even when bindings.lua fails or drops them.
require("rescue")
