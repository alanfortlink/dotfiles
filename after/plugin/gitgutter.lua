-- Jump to next / previous git change
vim.keymap.set("n", "gh", ":GitGutterNextHunk<CR>", { noremap = true})
vim.keymap.set("n", "gH", ":GitGutterPrevHunk<CR>", { noremap = true})
