-- Steam games run through Proton have the class steam_app_<id>; Wine and
-- Proton windows on the Wayland driver use the executable's name. The Steam
-- client itself is "steam" and matches neither. Native Linux games keep their
-- own class and are not covered.
hl.window_rule({
    name  = "games",
    match = { class = [[steam_app_\d+|.+\.exe]] },

    fullscreen = true,
    monitor    = "DP-1",
    -- immediate allows tearing; the game content type turns on direct
    -- scanout (looknfeel.lua).
    immediate  = true,
    content    = "game",
    -- The pointer otherwise escapes to DP-2 in fullscreen.
    -- WAIT-FOR closed: https://github.com/hyprwm/Hyprland/discussions/16249
    confine_pointer = true,
})

-- Critical notifications (quickshell/Notifications.qml) on the Overlay layer,
-- above fullscreen. Any Overlay surface on a game's monitor stops direct
-- scanout and tearing until it is gone, a fade-out included, so it comes and
-- goes at once.
hl.layer_rule({
    match  = { namespace = "^desk-notifications-critical$" },
    no_anim = true,
})

-- The calendar's big view (quickshell/CalendarFull.qml) blurs its whole
-- monitor. No ignore_alpha (which leaves unblurred every pixel at or below
-- its alpha), so the whole surface is blurred whatever the alpha of the
-- dimming drawn around the card.
hl.layer_rule({
    match = { namespace = "^desk-calendar-full$" },
    blur  = true,
})

-- desk-nest's nested compositor (README.md, "desk-nest"): its window goes to
-- the hidden special workspace "nest" without taking focus, and keeps
-- getting frame callbacks there, without which the nest draws one frame and
-- stops. Floating at a fixed size, because the nest's output takes the
-- window's size. The app id is aquamarine's Wayland backend's for any nested
-- aquamarine compositor, so any nested Hyprland matches, not only
-- desk-nest's. A pattern must match the whole string (Hyprland uses RE2's
-- FullMatch): a prefix such as "^aquamarine - " matches no title at all.
-- desk-nest checks where the window landed and corrects it if this misses.
hl.window_rule({
    name  = "desk-nest",
    match = { class = "aquamarine" },

    workspace        = "special:nest silent",
    no_initial_focus = true,
    render_unfocused = true,
    float            = true,
    size             = { 1600, 900 },
})
