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
