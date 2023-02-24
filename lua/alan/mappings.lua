local utils = require("alan.utils")

-- Window movement
vim.keymap.set("n", "<C-h>", "<C-w>h", { noremap = true })
vim.keymap.set("n", "<C-j>", "<C-w>j", { noremap = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { noremap = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { noremap = true })

-- Window resizing
vim.keymap.set("n", "<C-M-h>", "3<C-w><", { noremap = true })
vim.keymap.set("n", "<C-M-l>", "3<C-w>>", { noremap = true })
vim.keymap.set("n", "<C-M-k>", "1<C-w>-", { noremap = true })
vim.keymap.set("n", "<C-M-j>", "1<C-w>+", { noremap = true })
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
vim.keymap.set("n", "<C-d>", "<C-d>zz", { noremap = true })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { noremap = true })
vim.keymap.set("n", "<C-f>", "<C-f>zz", { noremap = true })
vim.keymap.set("n", "<C-b>", "<C-b>zz", { noremap = true })

vim.keymap.set("x", "<leader>d", "\"zd", { noremap = true })
vim.keymap.set("v", "<leader>d", "\"zd", { noremap = true })
vim.keymap.set("n", "<leader>d", "\"zd", { noremap = true })
vim.keymap.set("x", "<leader>y", "\"zy", { noremap = true })
vim.keymap.set("v", "<leader>y", "\"zy", { noremap = true })
vim.keymap.set("n", "<leader>y", "\"zy", { noremap = true })
vim.keymap.set("n", "<leader>p", "\"zp", { noremap = true })
vim.keymap.set("n", "<leader>P", "\"zP", { noremap = true })

vim.keymap.set("n", "<localleader>/", ":noh<CR>", { noremap = true })

-- Save / Restore a session.
vim.keymap.set("n", "<localleader>S1", ":mks! .session1.vim<CR>", { noremap = true })
vim.keymap.set("n", "<localleader>S2", ":mks! .session2.vim<CR>", { noremap = true })
vim.keymap.set("n", "<localleader>L1", ":so .session1.vim<CR>", { noremap = true })
vim.keymap.set("n", "<localleader>L2", ":so .session2.vim<CR>", { noremap = true })

-- NERDTree
vim.keymap.set("n", "<bslash><bslash>", ":NERDTreeToggle<CR>", { noremap = true })

-- Get git link for current line (BETA)
vim.keymap.set("n", "<localleader>gl", function()
  local gh_link = utils.get_github_link()
  print(gh_link)
  vim.fn.setreg("+", gh_link)
end, { noremap = true })
