-- DMS (DankMaterialShell) bridge: loads the DMS-managed compositor fragments
-- and adds DMS-specific layer rules. Part of the DMS switch — remove this
-- file (and its require in hyprland.lua) when going back to the Omarchy shell.

-- DMS-generated fragments (see `dms setup colors|layout|windowrules`):
-- DMS rewrites these when you change settings inside DMS.
require("hypr.dms.colors")
require("hypr.dms.layout")
require("hypr.dms.windowrules")

-- No compositor animations on DMS layer surfaces (bar, popups, spotlight).
hl.layer_rule({ match = { namespace = "dms" }, no_anim = true })
