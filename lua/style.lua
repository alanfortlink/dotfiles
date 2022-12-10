vim.o.number = true
vim.o.relativenumber = true
vim.o.cursorline = true
vim.o.cursorcolumn = true
vim.o.colorcolumn = 80
vim.o.mouse = true

vim.cmd([[
highlight WinSeparator guibg=None
hi Normal guibg=NONE ctermbg=NONE
hi EndOfBuffer guibg=NONE ctermbg=NONE
]])

vim.o.expandtab = true
vim.o.smarttab = true
vim.o.tabstop = 4
vim.o.shiftwidth = 4

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "dart" },
    callback = function()
        vim.o.shiftwidth = 4
        vim.o.tabstop = 4
    end
})

require('nvim-treesitter.configs').setup {
    -- ensure_installed = { "c", "cpp", "lua", "go", "dart", "python" },
    highlight = {
        enable = true,
    },
}

vim.o.background = "dark"
vim.cmd([[colorscheme codedark]])
