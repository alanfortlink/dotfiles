-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

-- Dual 4K at 1.5x fractional scaling.
hl.env("GDK_SCALE", "2")

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.6 })
hl.monitor({ output = "HDMI-A-1", mode = "3840x2160@60", position = "0x0", scale = 1.5 })
hl.monitor({ output = "DP-1", mode = "3840x2160@144", position = "2560x0", scale = 1.5 })

-- Pin workspaces: 1/3/4/5 on the Ultragear (DP-1), 2 on the Samsung (HDMI-A-1).
for _, ws in ipairs({ "1", "3", "4", "5" }) do
	hl.workspace_rule({ workspace = ws, monitor = "DP-1" })
end
hl.workspace_rule({ workspace = "2", monitor = "HDMI-A-1" })
