local wezterm = require 'wezterm'

return {
  font = wezterm.font('Pragmasevka Nerd Font'), -- Replace with your desired font family
  font_size = 16.0,

  window_background_image = '/home/alan/Downloads/ezgif-7-c3c0261f34.jpg', -- Replace with the path to your image
  window_background_image_hsb = {
    brightness = 0.025,
    hue = 1.0,
    saturation = 1.0,
  },

  window_background_opacity = 0.95, -- Adjust the opacity (0.0 - fully transparent, 1.0 - fully opaque)

  color_scheme = "onedark",
  enable_wayland = true,

  keys = {
    -- Bind Ctrl+Shift+R to reload the configuration
    { key = "R", mods = "CTRL|SHIFT", action = wezterm.action.ReloadConfiguration },
  },

}
