-- Matches the GNOME session: US layout with no XKB options, 500 ms repeat
-- delay at a 30 ms interval, libinput's default pointer acceleration, and
-- click to focus.
hl.config({
    input = {
        kb_layout    = "us",
        repeat_delay = 500,
        repeat_rate  = 33,
        -- Hovering does not take keyboard focus; clicking does.
        follow_mouse = 2,
    },
})
