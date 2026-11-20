-- Names are the kernel's connector names (/sys/class/drm).

-- No vrr: the PG278QR has a G-Sync module and no adaptive sync, so Hyprland
-- reports it as not VRR-capable on this AMD GPU.
hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
hl.monitor({ output = "DP-2", mode = "2560x1440@60", position = "2560x0", scale = 1 })

-- Capture card.
hl.monitor({ output = "HDMI-A-1", disabled = true })

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- Five workspaces per display. Must match the `workspaceMonitors` mapping in
-- quickshell/Bar.qml. While a monitor is off (game mode turns DP-2 off) its
-- workspaces move to, and are created on, the remaining one; when it comes
-- back, Hyprland moves every bound workspace back to its monitor.
for i = 1, 10 do
    local output = i <= 5 and "DP-1" or "DP-2"
    hl.workspace_rule({ workspace = tostring(i), monitor = output, default = i == 1 or i == 6 })
end
