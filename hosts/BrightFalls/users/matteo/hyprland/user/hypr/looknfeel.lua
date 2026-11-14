-- Dracula palette.
local purple     = "rgb(bd93f9)"
local pink       = "rgb(ff79c6)"
local selection  = "rgb(44475a)"
local background = "rgb(282a36)"

hl.config({
    general = {
        layout      = "dwindle",
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,
        col = {
            active_border   = { colors = { purple, pink }, angle = 45 },
            inactive_border = selection,
        },
        -- Lets windows with the immediate rule (rules.lua) tear.
        allow_tearing = true,
    },

    decoration = {
        rounding = 8,
        shadow = {
            enabled = true,
            range   = 8,
        },
        blur = {
            enabled = true,
            size    = 4,
            passes  = 2,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    render = {
        -- Auto-HDR washes out fullscreen colour on 0.57, and neither monitor
        -- does HDR.
        -- WAIT-FOR closed: https://github.com/hyprwm/Hyprland/discussions/16756
        cm_auto_hdr    = 0,
        -- Scan out directly only for windows with the game content type.
        direct_scanout = 2,
    },

    misc = {
        -- Edits apply only on reload (Super+Shift+R, rescue.lua), never in
        -- the middle of a multi-file change or a game.
        disable_autoreload      = true,
        disable_hyprland_logo   = true,
        force_default_wallpaper = 0,
        background_color        = background,
    },
})

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })

hl.animation({ leaf = "global",     enabled = true, speed = 8, bezier = "default" })
hl.animation({ leaf = "windows",    enabled = true, speed = 4, bezier = "easeOutQuint", style = "popin 90%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3, bezier = "easeOutQuint" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "easeOutQuint", style = "fade" })
