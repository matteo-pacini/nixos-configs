-- Same layout as GNOME's hosts/BrightFalls/monitors.xml. Names are the
-- kernel's connector names (/sys/class/drm), so mutter's HDMI-1 is HDMI-A-1.

-- No vrr: the PG278QR has a G-Sync module and no adaptive sync, so Hyprland
-- reports it as not VRR-capable on this AMD GPU.
hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
hl.monitor({ output = "DP-2", mode = "2560x1440@60", position = "2560x0", scale = 1 })

-- Capture card.
hl.monitor({ output = "HDMI-A-1", disabled = true })

-- Anything else goes to the right at its preferred mode.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
