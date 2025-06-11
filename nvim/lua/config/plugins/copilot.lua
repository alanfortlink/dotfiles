vim.keymap.set("i", "<C-l>", 'copilot#Accept("<CR>")', {
	expr = true,
	replace_keycodes = false,
	silent = true,
})
vim.keymap.set("i", "<C-h>", 'copilot#AcceptWord("<CR>")', {
	expr = true,
	replace_keycodes = false,
	silent = true,
})
vim.g.copilot_no_tab_map = true

return {
	{ "github/copilot.vim" },
}
