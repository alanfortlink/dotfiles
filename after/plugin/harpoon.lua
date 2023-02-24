require("harpoon").setup({})

local mark = require("harpoon.mark")
local ui = require("harpoon.ui")

vim.keymap.set("n", "<localleader>s", mark.add_file)
vim.keymap.set("n", "<localleader>r", mark.rm_file)
vim.keymap.set("n", "<localleader>a", ui.toggle_quick_menu)

vim.keymap.set("n", "<localleader>n", ui.nav_next)
vim.keymap.set("n", "<localleader>p", ui.nav_prev)

for i = 1, 9 do vim.keymap.set("n", "<localleader>" .. i, function() ui.nav_file(i) end) end
