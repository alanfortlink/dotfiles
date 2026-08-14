-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

-- Dual 4K at 1.5x fractional scaling.
hl.env("GDK_SCALE", "1.5")

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2 })
hl.monitor({ output = "HDMI-A-1", mode = "3840x2160@60", position = "0x0", scale = 1.5 })
hl.monitor({ output = "DP-1", mode = "3840x2160@144", position = "2560x0", scale = 1.5 })
