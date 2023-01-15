vim.g.mapleader = ","
vim.g.maplocalleader = " "

vim.opt.undodir = os.getenv("HOME") .. "/.config/nvim/undo"
vim.opt.undofile = true

vim.opt.wildignore = "**/cmake.bld/**,compile_commands.json"

vim.opt.autoindent = true
vim.opt.cmdheight = 1
vim.opt.colorcolumn = "80"
vim.opt.completeopt = "menuone,noinsert,noselect"
vim.opt.errorbells = false
vim.opt.exrc = true
vim.opt.hidden = true
vim.opt.hlsearch = true
vim.opt.smartcase = true
vim.opt.incsearch = true
vim.opt.scrolloff = 0
vim.opt.shortmess:append("c")
vim.opt.isfname:append("@-@")
vim.opt.signcolumn = "yes"
vim.opt.smartindent = true
vim.opt.guicursor = ""
vim.opt.swapfile = false
vim.opt.wrap = false
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.updatetime = 50
vim.opt.shortmess:append("c")

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.cursorcolumn = true
vim.opt.colorcolumn = "80"

vim.cmd([[
highlight WinSeparator guibg=None
hi Normal guibg=NONE ctermbg=NONE
hi EndOfBuffer guibg=NONE ctermbg=NONE
]])

vim.opt.expandtab = true
vim.opt.smarttab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4

vim.opt.background = "dark"
-- vim.cmd.colorscheme("gruvbox")
