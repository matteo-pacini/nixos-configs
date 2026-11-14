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
-- It is the read-only copy under ~/.local/share/desk (see
-- hosts/BrightFalls/users/matteo/hyprland/README.md in nixos-configs), out
-- of reach of live edits, so it goes by absolute path, which Hyprland's
-- require() resolves as a file. pcall: a missing file would raise here.
local data = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
pcall(require, data .. "/desk/hypr/rescue.lua")
