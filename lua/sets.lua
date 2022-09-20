vim.g.mapleader = ','
vim.g.maplocalleader = ' '

vim.o.undodir = os.getenv("HOME") .. "/.config/nvim/undo"
vim.o.undofile = true

vim.o.syntax = true

vim.o.wildignore = '**/cmake.bld/**,compile_commands.json'

vim.o.autoindent = true
vim.o.cmdheight = 1
vim.o.colorcolumn = 80
vim.o.completeopt = 'menuone,noinsert,noselect'
vim.o.errorbells = false
vim.o.exrc = true
vim.o.hidden = true
vim.o.hlsearch = true
vim.o.ignorecase = true
vim.o.incsearch = true
vim.o.scrolloff = 1
vim.o.shortmess = 'c'
vim.o.signcolumn = 'yes'
vim.o.smartindent = true
vim.o.swapfile = false
vim.o.wrap = false
vim.o.splitright = true
vim.o.splitbelow = true
vim.opt.updatetime = 50
vim.opt.shortmess:append("c")
