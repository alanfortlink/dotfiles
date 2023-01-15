local mark = require("harpoon.mark")
local ui = require("harpoon.ui")

vim.keymap.set("n", "<localleader>a", mark.add_file)
vim.keymap.set("n", "<localleader>A", ui.toggle_quick_menu())

vim.keymap.set("n", "<localleader>n", ui.nav_next())
vim.keymap.set("n", "<localleader>p", ui.nav_prev())
