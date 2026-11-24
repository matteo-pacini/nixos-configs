-- The nested compositor desk-nest starts (README.md, "desk-nest"). No exec
-- at top level (it runs on every parse), no binds on SUPER (the host takes
-- those first), no XWayland (an X socket in /tmp and a DISPLAY of its own).
-- desk-nest replaces the first output with DP-1, named as the real left
-- monitor; its size is the host window's, set by the window rule in
-- user/hypr/rules.lua.
hl.monitor({ output = "", mode = "1600x900", position = "0x0", scale = 1 })
hl.config({
    xwayland = { enabled = false },
    misc = {
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
        disable_autoreload = true,
        disable_watchdog_warning = true,
        disable_hyprland_guiutils_check = true,
    },
    ecosystem = { no_update_news = true, no_donation_nag = true },
})
-- ALT + SHIFT + E is free on the host.
hl.bind("ALT + SHIFT + E", hl.dsp.exit())
