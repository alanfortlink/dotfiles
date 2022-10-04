vim.g.mapleader = ','
vim.g.maplocalleader = ' '

vim.opt.undodir = os.getenv("HOME") .. "/.config/nvim/undo"
vim.opt.undofile = true

vim.opt.syntax = true

vim.opt.wildignore = '**/cmake.bld/**,compile_commands.json'

vim.opt.autoindent = true
vim.opt.cmdheight = 1
vim.opt.colorcolumn = 80
vim.opt.completeopt = 'menuone,noinsert,noselect'
vim.opt.errorbells = false
vim.opt.exrc = true
vim.opt.hidden = true
vim.opt.hlsearch = true
vim.opt.ignorecase = true
vim.opt.incsearch = true
vim.opt.scrolloff = 0
vim.opt.shortmess:append("c")
vim.opt.isfname:append("@-@")
vim.opt.signcolumn = 'yes'
vim.opt.smartindent = true
vim.opt.guicursor = ""
vim.opt.swapfile = false
vim.opt.wrap = false
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.updatetime = 50
vim.opt.shortmess:append("c")
