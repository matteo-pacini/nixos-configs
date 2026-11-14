-- Colours and fonts come from ~/.config/desk/theme.json through the
-- read-only theme.lua beside rescue.lua, by absolute path for the same reason
-- (see hyprland.lua). pcall: the file is missing if that directory is. Any
-- key it does not supply falls back to the Dracula value here.
local data = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
local ok, theme = pcall(require, data .. "/desk/hypr/theme.lua")
if not ok or type(theme) ~= "table" then
    theme = {}
end
local fallback = {
    background   = "#282a36",
    current_line = "#44475a",
    pink         = "#ff79c6",
    purple       = "#bd93f9",
    font_ui      = "Fira Sans",
}
local function pick(key)
    return theme[key] or fallback[key]
end
local function rgb(key)
    return "rgb(" .. pick(key):sub(2) .. ")"
end

local purple       = rgb("purple")
local pink         = rgb("pink")
local current_line = rgb("current_line")
local background   = rgb("background")

hl.config({
    general = {
        layout      = "dwindle",
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,
        col = {
            active_border   = { colors = { purple, pink }, angle = 45 },
            inactive_border = current_line,
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
        -- Hyprland's own text: config errors and hyprctl notify.
        font_family             = pick("font_ui"),
    },
})

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })

hl.animation({ leaf = "global",     enabled = true, speed = 8, bezier = "default" })
hl.animation({ leaf = "windows",    enabled = true, speed = 4, bezier = "easeOutQuint", style = "popin 90%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3, bezier = "easeOutQuint" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "easeOutQuint", style = "fade" })
