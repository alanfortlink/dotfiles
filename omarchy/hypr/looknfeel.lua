hl.config({
	general = {
		gaps_in = 2,
		gaps_out = 2,

		-- White highlight around the active window (overrides theme).
		col = {
			active_border = "rgb(ffffff)",
			inactive_border = "rgba(ffffff00)",
		},
	},

	decoration = {
		rounding = 8,
	},

	-- Keep scratchpads visible on their monitor when focus moves to another
	-- monitor. Omarchy default is true (hides them).
	binds = {
		hide_special_on_workspace_change = false,
	},
})

-- >>> omaland managed block >>>
-- Written by Omaland. Safe to hand-edit: Omaland re-reads this block
-- every time it opens, and only ever rewrites what's between the fences.
hl.config({
  animations = {
    workspace_wraparound = true,
  },

  decoration = {
    active_opacity = 1,
    border_part_of_window = true,
    dim_around = 0.2,
    dim_inactive = false,
    dim_modal = true,
    dim_special = 0.21,
    rounding_power = 10,

    blur = {
      enabled = false,
      size = 16,
    },

    glow = {
      enabled = false,
      range = 2,
    },

    shadow = {
      enabled = true,
      range = 10,
    },
  },

  dwindle = {
    preserve_split = false,
    smart_split = false,
  },

  general = {
    border_size = 1,
    float_gaps = 5,
    layout = "dwindle",

    snap = {
      enabled = false,
    },
  },

  master = {
    mfact = 0.55,
    new_status = "inherit",
  },
})
-- <<< omaland managed block <<<
