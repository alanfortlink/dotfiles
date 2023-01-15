local utils = require("utils")

-- Window movement
vim.keymap.set("n", "<C-h>", "<C-w>h", {noremap = true})
vim.keymap.set("n", "<C-j>", "<C-w>j", {noremap = true})
vim.keymap.set("n", "<C-k>", "<C-w>k", {noremap = true})
vim.keymap.set("n", "<C-l>", "<C-w>l", {noremap = true})

-- Window resizing
vim.keymap.set("n", "<C-M-h>", "3<C-w><")
vim.keymap.set("n", "<C-M-l>", "3<C-w>>")
vim.keymap.set("n", "<C-M-k>", "1<C-w>-")
vim.keymap.set("n", "<C-M-j>", "1<C-w>+")
vim.keymap.set("n", "<leader>M", "<C-w>_<C-w><Bar> ")
vim.keymap.set("n", "<leader>m", "<C-w>=")

-- Tab / Panel creation
vim.keymap.set("n", "<leader>t", ":tabnew<CR>")
vim.keymap.set("n", "<leader>n", ":new<CR>")
vim.keymap.set("n", "<leader>v", ":vnew<CR>")
vim.keymap.set("n", "<leader>q", ":q<CR>")
vim.keymap.set("n", "<leader>Q", ":q!<CR>")

-- Quickly go-to-tab
for tab = 1, 9 do vim.keymap.set("n", "<leader>" .. tab, tab .. "gt") end

-- Re-center buffer when jumping up and down
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "<C-f>", "<C-f>zz")
vim.keymap.set("n", "<C-b>", "<C-b>zz")

vim.keymap.set("n", "<localleader>/", ":noh<CR>")

-- Save / Restore a session.
vim.keymap.set("n", "<localleader>s1", ":mks! .session1.vim<CR>")
vim.keymap.set("n", "<localleader>s2", ":mks! .session2.vim<CR>")
vim.keymap.set("n", "<localleader>l1", ":so .session1.vim<CR>")
vim.keymap.set("n", "<localleader>l2", ":so .session2.vim<CR>")

-- NERDTree
vim.keymap.set("n", "<bslash><bslash>", ":NERDTreeToggle<CR>")

-- Get git link for current line (BETA)
vim.keymap.set("n", "<localleader>gl", function()
    local gh_link = utils.get_github_link()
    print(gh_link)
    vim.fn.setreg("+", gh_link)
end)
