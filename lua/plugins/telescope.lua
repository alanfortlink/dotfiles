local telescope = require("telescope.builtin")

-- Nice find files
vim.keymap.set("n", "<leader>f", function() telescope.find_files({ hidden = false }) end)

-- Messy find files
vim.keymap.set("n", "<leader>F", function() telescope.find_files({ hidden = true }) end)

-- Commands
vim.keymap.set("n", "<localleader>c", telescope.commands)
vim.keymap.set("n", "<localleader>h", telescope.help_tags)

-- Almighty GREP
vim.keymap.set("n", "<leader>g", telescope.live_grep)

-- Other telescope stuff
vim.keymap.set("n", "<localleader>d", telescope.lsp_definitions)
vim.keymap.set("n", "<localleader>t", telescope.lsp_type_definitions)

vim.keymap.set("n", "<localleader><localleader>", telescope.resume)
