local wezterm = require 'wezterm'

local session_manager = require 'wezterm-session-manager.session-manager'

wezterm.on("save_session", function(window) session_manager.save_state(window) end)
wezterm.on("load_session", function(window) session_manager.load_state(window) end)
wezterm.on("restore_session", function(window) session_manager.restore_state(window) end)

return {
  font = wezterm.font('Pragmasevka Nerd Font'), -- Replace with your desired font family
  font_size = 20.0,
  window_background_image_hsb = {
    brightness = 0.010,
    hue = 1.0,
    saturation = 1.0,
  },
  -- save and restore tabs/panes
  enable_tab_bar = true,
  window_close_confirmation = "NeverPrompt",
  window_frame = {
    -- this helps preserve title bar integration
    font_size = 13.0,
  },


  window_background_opacity = 0.75, -- Adjust the opacity (0.0 - fully transparent, 1.0 - fully opaque)
  macos_window_background_blur = 100,

  color_scheme = "onedark",
  enable_wayland = true,

  keys = {
    -- Bind Ctrl+Shift+R to reload the configuration
    { key = "R", mods = "CTRL|SHIFT", action = wezterm.action.ReloadConfiguration },
    { key = "n", mods = "OPT",        action = wezterm.action.SplitVertical },
    { key = "v", mods = "OPT",        action = wezterm.action.SplitHorizontal },
    { key = "q", mods = "OPT",        action = wezterm.action.CloseCurrentPane({ confirm = false }) },

    { key = "w", mods = "OPT",        action = wezterm.action{EmitEvent = "save_session"} },
    { key = "r", mods = "OPT",        action = wezterm.action{EmitEvent = "restore_session"} },

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

    {
      key = "u",
      mods = "OPT",
      action = wezterm.action.Multiple {
        wezterm.action.ActivateCopyMode,
        wezterm.action.CopyMode("MoveUp"),
        wezterm.action.CopyMode("MoveUp"),
        wezterm.action.CopyMode("MoveUp"),
        wezterm.action.CopyMode("MoveUp"),
        wezterm.action.CopyMode("MoveUp"),
        wezterm.action.CopyMode("MoveUp"),
        wezterm.action.CopyMode("MoveUp"),
        wezterm.action.CopyMode("MoveUp"),
        wezterm.action.CopyMode("MoveUp"),
        wezterm.action.CopyMode("MoveUp"),
      },
    },
    {
      key = "d",
      mods = "OPT",
      action = wezterm.action.Multiple {
        wezterm.action.ActivateCopyMode,
        wezterm.action.CopyMode("MoveDown"),
        wezterm.action.CopyMode("MoveDown"),
        wezterm.action.CopyMode("MoveDown"),
        wezterm.action.CopyMode("MoveDown"),
        wezterm.action.CopyMode("MoveDown"),
        wezterm.action.CopyMode("MoveDown"),
        wezterm.action.CopyMode("MoveDown"),
        wezterm.action.CopyMode("MoveDown"),
        wezterm.action.CopyMode("MoveDown"),
        wezterm.action.CopyMode("MoveDown"),
      }
    },

    -- Enter copy mode
    { key = "y", mods = "OPT", action = wezterm.action.ActivateCopyMode },
  },
}
