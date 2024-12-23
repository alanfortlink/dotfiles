return {
  "ThePrimeagen/harpoon",
  lazy = false,
  config = function()
    require("harpoon").setup({})

    local mark = require("harpoon.mark")
    local ui = require("harpoon.ui")

    vim.keymap.set("n", "<localleader>s", mark.add_file, { noremap = true })
    vim.keymap.set("n", "<localleader>r", mark.rm_file, { noremap = true })
    vim.keymap.set("n", "<localleader>a", ui.toggle_quick_menu, { noremap = true })

    for i = 1, 9 do vim.keymap.set("n", "<localleader>" .. i, function() ui.nav_file(i) end, { noremap = true }) end
  end,
}
