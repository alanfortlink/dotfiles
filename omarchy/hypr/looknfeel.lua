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
