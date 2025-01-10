local utils = require("utils")

-- Window movement
vim.keymap.set("n", "<C-h>", "<C-w>h", { noremap = true })
vim.keymap.set("n", "<C-j>", "<C-w>j", { noremap = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { noremap = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { noremap = true })

-- Window resizing
vim.keymap.set("n", "-", "<cmd>horizontal resize -5<CR>", { noremap = true })
vim.keymap.set("n", "=", "<cmd>horizontal resize +5<CR>", { noremap = true })
vim.keymap.set("n", "_", "<cmd>vertical resize -5<CR>", { noremap = true })
vim.keymap.set("n", "+", "<cmd>vertical resize +5<CR>", { noremap = true })
vim.keymap.set("n", "<leader>M", "<C-w>_<C-w><Bar> ", { noremap = true })
vim.keymap.set("n", "<leader>m", "<C-w>=", { noremap = true })

-- Tab / Panel creation
vim.keymap.set("n", "<leader>t", ":tabnew<CR>", { noremap = true })
vim.keymap.set("n", "<leader>n", ":new<CR>", { noremap = true })
vim.keymap.set("n", "<leader>v", ":vnew<CR>", { noremap = true })
vim.keymap.set("n", "<leader>q", ":q<CR>", { noremap = true })
vim.keymap.set("n", "<leader>Q", ":q!<CR>", { noremap = true })

-- Quickly go-to-tab
for tab = 1, 9 do vim.keymap.set("n", "<leader>" .. tab, tab .. "gt", { noremap = true }) end

-- Re-center buffer when jumping up and down
vim.keymap.set("n", "n", "nzz", { noremap = true })
vim.keymap.set("n", "N", "Nzz", { noremap = true })
vim.keymap.set("n", "<C-d>", "<C-d>zz", { noremap = true })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { noremap = true })
vim.keymap.set("n", "<C-f>", "<C-f>zz", { noremap = true })
vim.keymap.set("n", "<C-b>", "<C-b>zz", { noremap = true })

vim.keymap.set("x", "<leader>d", '"+d', { noremap = true })
vim.keymap.set("v", "<leader>d", '"+d', { noremap = true })
vim.keymap.set("n", "<leader>d", '"+d', { noremap = true })
vim.keymap.set("x", "<leader>y", '"+y', { noremap = true })
vim.keymap.set("v", "<leader>y", '"+y', { noremap = true })
vim.keymap.set("n", "<leader>y", '"+y', { noremap = true })
vim.keymap.set("n", "<leader>p", '"+p', { noremap = true })
vim.keymap.set("n", "<leader>P", '"+P', { noremap = true })

vim.keymap.set("n", "<localleader>/", ":noh<CR>", { noremap = true })

-- Save / Restore a session.
vim.keymap.set("n", "<localleader>Sj", ":mks! .sesj.vim<CR>", { noremap = true })
vim.keymap.set("n", "<localleader>Sk", ":mks! .sesk.vim<CR>", { noremap = true })
vim.keymap.set("n", "<localleader>lj", ":so .sesj.vim<CR>", { noremap = true })
vim.keymap.set("n", "<localleader>lk", ":so .sesk.vim<CR>", { noremap = true })

-- Run
vim.keymap.set("n", "<leader>r", ":silent !make run<CR>", { noremap = true })
vim.keymap.set("n", "<leader>R", ":!make run<CR>", { noremap = true })

-- Get git link for current line (BETA)
vim.keymap.set("n", "<localleader>gl", function()
  local link = utils.get_github_link()
  vim.fn.setreg("+", link)
  print(link)
end, { noremap = true })

local augroup = vim.api.nvim_create_augroup("augroup1", { clear = true })

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

vim.keymap.set("n", "<localleader>o", "<cmd>copen<CR>", { noremap = true })
vim.keymap.set("n", "<localleader>O", "<cmd>cclose<CR>", { noremap = true })
vim.keymap.set("n", "]q", "<cmd>cnext<CR>zz", { noremap = true })
vim.keymap.set("n", "[q", "<cmd>cprevious<CR>zz", { noremap = true })

vim.keymap.set("n", "<localleader>x", ":.lua<CR>", { noremap = true })
vim.keymap.set("n", "<localleader>xx", ":%lua<CR>", { noremap = true })
vim.keymap.set("v", "<localleader>x", ":lua<CR>", { noremap = true })

vim.keymap.set("v", "<localleader>", ":lua<CR>", { noremap = true })

vim.keymap.set({ "n" }, "<Esc>", ":nohl<CR>", { noremap = true, silent = true })
vim.keymap.set({ "t" }, "<Esc><Esc>", "<C-\\><C-n>:ToggleTerminal<CR>", { noremap = true, silent = true })
vim.keymap.set({ "t" }, "<Esc><Esc><Esc>", "<C-\\><C-n>", { noremap = true })

vim.keymap.set("n", "<localleader>t", ":ToggleTerminal<CR>", { noremap = true, silent = true })
vim.keymap.set('n', '<localleader>q', ':KillTerminal<CR>', { noremap = true, silent = true })
