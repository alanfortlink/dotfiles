-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.envs")
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")
require("hypr.gif-captioner")
require("hypr.layout")
require("hypr.layout-rules")
require("hypr.deadlock-overlay")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- [key-visualizer] capture hook (managed by the plugin; safe to remove)
local kc_path = os.getenv("HOME") .. "/.config/omarchy/plugins/felixzsh.key-visualizer/key-visualizer.lua"
local kc_file = io.open(kc_path, "r")
if kc_file then kc_file:close(); dofile(kc_path) end

-- === DMS (DankMaterialShell) switch: compositor fragments ===
-- Loads DMS-managed colors/layout/window rules plus DMS layer rules.
-- Remove this block (together with hypr/dms.lua and hypr/dms/) when going
-- back to the Omarchy shell.
require("hypr.dms")
