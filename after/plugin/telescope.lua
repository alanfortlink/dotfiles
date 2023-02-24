local telescope = require("telescope.builtin")

-- Nice find files
vim.keymap.set("n", "<leader>f", function() telescope.find_files({ hidden = false }) end, { noremap = true })

-- Messy find files
vim.keymap.set("n", "<leader>F", function() telescope.find_files({ hidden = true }) end, { noremap = true })

-- Commands
vim.keymap.set("n", "<localleader>c", telescope.commands, { noremap = true })
vim.keymap.set("n", "<localleader>h", telescope.help_tags, { noremap = true })

-- Almighty GREP
vim.keymap.set("n", "<leader>g", telescope.live_grep, { noremap = true })

-- Other telescope stuff
vim.keymap.set("n", "<localleader>d", telescope.lsp_definitions, { noremap = true })
vim.keymap.set("n", "<localleader>t", telescope.lsp_type_definitions, { noremap = true })

vim.keymap.set("n", "<localleader><localleader>", telescope.resume, { noremap = true })
vim.keymap.set("n", "<leader><localleader>", telescope.builtin, { noremap = true })
