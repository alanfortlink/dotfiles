vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.cursorcolumn = true
vim.opt.colorcolumn = "80"

-- vim.cmd([[
-- highlight WinSeparator guibg=None
-- hi Normal guibg=NONE ctermbg=NONE
-- hi EndOfBuffer guibg=NONE ctermbg=NONE
-- ]])

vim.opt.expandtab = true
vim.opt.smarttab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "dart" },
    callback = function()
        vim.opt.shiftwidth = 4
        vim.opt.tabstop = 4
    end
})

require('nvim-treesitter.configs').setup {
    -- ensure_installed = { "c", "cpp", "lua", "go", "dart", "python" },
    highlight = {
        enable = true,
    },
}

vim.opt.background = "dark"
vim.cmd.colorscheme("codedark")

require('lualine').setup({
    options = {
        icons_enabled = true,
        theme = 'auto',
        component_separators = { left = '', right = '' },
        section_separators = { left = '', right = '' },
        disabled_filetypes = {},
        always_divide_middle = true,
        globalstatus = false,
    },
    sections = {
        lualine_a = { 'mode' },
        lualine_b = { 'branch', 'diff', 'diagnostics' },
        lualine_c = { 'filename' },
        lualine_x = { 'filesize', 'encoding', 'filetype' },
        lualine_y = { 'progress' },
        lualine_z = { 'location' }
    },
    tabline = {},
    extensions = {}
})
