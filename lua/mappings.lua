local utils = require("utils")

-- Window movement
vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-l>", "<C-w>l")

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

-- Copy / Paste from special register
vim.keymap.set("n", "<leader>d", '"Zd')
vim.keymap.set("v", "<leader>d", '"Zd')
vim.keymap.set("x", "<leader>d", '"Zd')
vim.keymap.set("n", "<leader>y", '"Zy')
vim.keymap.set("v", "<leader>y", '"Zy')
vim.keymap.set("x", "<leader>y", '"Zy')
vim.keymap.set("n", "<leader>p", '"Zp')
vim.keymap.set("n", "<leader>P", '"ZP')

-- Jump to next / previous git change
vim.keymap.set("n", "gh", ":GitGutterNextHunk<CR>")
vim.keymap.set("n", "gH", ":GitGutterPrevHunk<CR>")

-- Re-center buffer when jumping up and down
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "<C-f>", "<C-f>zz")
vim.keymap.set("n", "<C-b>", "<C-b>zz")

local telescope = require("telescope.builtin")

-- Nice find files
vim.keymap.set("n", "<leader>f", function() telescope.find_files({ hidden = false }) end)

-- Messy find files
vim.keymap.set("n", "<leader>F", function() telescope.find_files({ hidden = true }) end)

-- Commands
vim.keymap.set("n", "<localleader>c", telescope.commands)
vim.keymap.set("n", "<localleader>h", telescope.help_tags)

-- Almighty GREP
vim.keymap.set("n", "<leader>g", telescope.live_grep)

-- Other telescope stuff
vim.keymap.set("n", "<localleader>d", telescope.lsp_definitions)
vim.keymap.set("n", "<localleader>t", telescope.lsp_type_definitions)

-- Undo tree
vim.keymap.set("n", "<localleader>/", ":noh<CR>")
vim.keymap.set("n", "<localleader>u", ":UndotreeShow<CR>:UndotreeFocus<CR>")
vim.keymap.set("n", "<localleader>U", ":UndotreeHide<CR>")

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
