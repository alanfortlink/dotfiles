local wezterm = require 'wezterm'

return {
  font = wezterm.font('Pragmasevka Nerd Font'), -- Replace with your desired font family
  font_size = 18.0,
  window_background_image_hsb = {
    brightness = 0.010,
    hue = 1.0,
    saturation = 1.0,
  },

  window_background_opacity = 0.95, -- Adjust the opacity (0.0 - fully transparent, 1.0 - fully opaque)

  color_scheme = "onedark",
  enable_wayland = true,

  keys = {
    -- Bind Ctrl+Shift+R to reload the configuration
    { key = "R", mods = "CTRL|SHIFT", action = wezterm.action.ReloadConfiguration },
    { key = "n", mods = "ALT",        action = wezterm.action.SplitVertical },
    { key = "v", mods = "ALT",        action = wezterm.action.SplitHorizontal },
    { key = "q", mods = "ALT",        action = wezterm.action.CloseCurrentPane({ confirm = false }) },

    { key = "h", mods = "OPT",        action = wezterm.action.ActivatePaneDirection "Left" },
    { key = "j", mods = "OPT",        action = wezterm.action.ActivatePaneDirection "Down" },
    { key = "k", mods = "OPT",        action = wezterm.action.ActivatePaneDirection "Up" },
    { key = "l", mods = "OPT",        action = wezterm.action.ActivatePaneDirection "Right" },
    { key = "z", mods = "OPT",        action = wezterm.action.TogglePaneZoomState },

    { key = "h", mods = "OPT|SHIFT",  action = wezterm.action.AdjustPaneSize { "Left", 50 } },
    { key = "j", mods = "OPT|SHIFT",  action = wezterm.action.AdjustPaneSize { "Down", 50 } },
    { key = "k", mods = "OPT|SHIFT",  action = wezterm.action.AdjustPaneSize { "Up", 50 } },
    { key = "l", mods = "OPT|SHIFT",  action = wezterm.action.AdjustPaneSize { "Right", 50 } },

    { key = "c", mods = "OPT",        action = wezterm.action.SpawnTab "CurrentPaneDomain" },
    { key = "1", mods = "OPT",        action = wezterm.action.ActivateTab(0) },
    { key = "2", mods = "OPT",        action = wezterm.action.ActivateTab(1) },
    { key = "3", mods = "OPT",        action = wezterm.action.ActivateTab(2) },
    { key = "4", mods = "OPT",        action = wezterm.action.ActivateTab(3) },
    { key = "5", mods = "OPT",        action = wezterm.action.ActivateTab(4) },
    { key = "6", mods = "OPT",        action = wezterm.action.ActivateTab(5) },
    { key = "7", mods = "OPT",        action = wezterm.action.ActivateTab(6) },
    { key = "8", mods = "OPT",        action = wezterm.action.ActivateTab(7) },
    { key = "9", mods = "OPT",        action = wezterm.action.ActivateTab(8) },

    { key = "u", mods = "OPT",        action = wezterm.action.Multiple { wezterm.action.ActivateCopyMode, wezterm.action.CopyMode("MoveUp") } },
    { key = "d", mods = "OPT",        action = wezterm.action.Multiple { wezterm.action.ActivateCopyMode, wezterm.action.CopyMode("MoveDown") } },

    -- Enter copy mode
    { key = "y", mods = "OPT",        action = wezterm.action.ActivateCopyMode },
  },
}
