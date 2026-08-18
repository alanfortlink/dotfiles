-- LayoutRR user overrides. This file is YOURS: hand-edit freely, it is never
-- regenerated. It is re-read on every save/restore, no `hyprctl reload`
-- needed. Anything left out falls back to the defaults in layout.lua.
--
-- Placeholders in commands: {url} -> urls[<workspace>] for that row.
return {
  -- class -> launch command. Classes not listed here are resolved as:
  --   chrome-web.<domain>__-Default  -> omarchy-launch-webapp https://<domain>/
  --   <class>.desktop exists          -> gtk-launch <class>
  --   otherwise                       -> <class> (run as a command)
  commands = {
    -- --gtk-single-instance=false: a fresh process per window, so Hyprland's
    -- per-PID exec rules (tag + staging workspace) can attach to it.
    ["com.mitchellh.ghostty"] = "ghostty --gtk-single-instance=false",
    ["org.telegram.desktop"] = "telegram-desktop",
    ["chrome-web.whatsapp.com__-Default"] = "omarchy-launch-webapp https://web.whatsapp.com/",
    ["chromium"] = "chromium --new-window",
    ["org.omarchy.agent"] = "omarchy agent",
    ["localsend"] = "gtk-launch localsend",
    ["org.localsend.localsend_app"] = "gtk-launch localsend",
    ["google-chrome"] = "google-chrome-stable --new-window {url}",
    ["steam"] = "steam",
    ["discord"] = "discord",
  },

  -- Classes whose launch command hands the window off to an already-running
  -- process (so Hyprland's per-PID exec rules can't tag/file the window).
  -- These are launched strictly one at a time and claimed as "first new
  -- window of that class since the launch".
  no_pid_rules = {
    ["google-chrome"] = true,
    ["chromium"] = true,
  },

  -- Saved class -> class the app maps with today (app-id changed after an update).
  aliases = {
    ["localsend"] = "org.localsend.localsend_app",
  },

  -- workspace -> URL substituted for {url} (google-chrome slots). Workspaces
  -- without an entry get an empty {url} (blank window).
  urls = {
    ["2"] = "https://youtube.com",
    ["special:scratchpad"] = "https://claude.ai/code",
    ["special:scratch2"] = "https://mail.google.com",
  },

  -- Splash-screen apps: they map a loader window first, so they are placed by
  -- the static rules in layout-rules.lua (regenerated on save) instead of by
  -- the restore engine. Launched, but never claimed/placed/verified.
  splashy = {
    steam = true,
    discord = true,
  },

  -- Classes never saved nor restored: exact class names (`["foo"] = true`)
  -- or Lua patterns given as list entries. Steam games map as
  -- steam_app_<id>: they can't be relaunched, so keep them out of the spec.
  ignore = { "^steam_app_%d+$" },

  timeouts = {
    monitors = 15000,   -- ms to wait for the monitors named in the spec
    window = 30000,     -- ms per launched window before it's marked FAILED
    total = 120000,     -- ms hard cap for the whole run
    resize_passes = 6,  -- measure-and-correct passes per workspace
    step = 60,          -- ms between compositor steps inside a workspace
  },
  tolerance_px = 4,
}
