-- Change the default Omarchy look'n'feel.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/

hl.config({
  general = {
    -- Near-zero gaps between windows and borders.
    gaps_in = 1,
    gaps_out = 1,

    -- White highlight around the active window (overrides theme).
    col = {
      active_border = "rgb(ffffff)",
    },
  },

  decoration = {
    rounding = 14,

    -- White glow around the active window.
    shadow = {
      enabled = true,
      range = 8,
      render_power = 3,
      color = "rgba(ffffff80)",
      color_inactive = "rgba(00000000)",
    },
  },

  group = {
    col = {
      border_active = "rgb(ffffff)",
    },
  },

  -- Keep scratchpads visible on their monitor when focus moves to another
  -- monitor. Omarchy default is true (hides them).
  binds = {
    hide_special_on_workspace_change = false,
  },
})
