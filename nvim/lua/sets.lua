vim.g.mapleader = ","
vim.g.maplocalleader = " "

vim.g.godot_executable = '/Applications/Godot.app/Contents/MacOS/Godot'
vim.opt.undodir = os.getenv("HOME") .. "/.vim_undo"
vim.opt.wildignore = "**/cmake.bld/**,compile_commands.json"
vim.g.have_nerd_font = true
vim.opt.wrap = false

vim.opt.undofile = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = 'a'
vim.opt.showmode = false
-- vim.opt.clipboard = 'unnamed'
vim.opt.swapfile = false
vim.opt.breakindent = true
vim.opt.undofile = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.signcolumn = 'yes'
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300

vim.opt.splitright = true
vim.opt.splitbelow = true

vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

vim.opt.inccommand = 'split'
vim.opt.cursorline = true
vim.opt.scrolloff = 0
vim.opt.hlsearch = true

vim.opt.expandtab = true
vim.opt.smarttab = true
vim.opt.smartindent = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2

vim.g.neovide_transparency = 0.8
vim.g.neovide_blue = true
