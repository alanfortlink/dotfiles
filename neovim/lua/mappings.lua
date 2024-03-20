local utils = require("utils")

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

-- Get git link for current line (BETA)
vim.keymap.set("n", "<localleader>gl", function()
  print(utils.get_github_link())
end, { noremap = true })

local augroup = vim.api.nvim_create_augroup("augroup1", { clear = true })

-- Update git gutter on save
vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = { "*" },
    callback = function()
        vim.cmd("GitGutter")
    end,
    group = augroup
})

-- Jump between .h/.cpp and go to local CMakeLists.txt
vim.api.nvim_create_autocmd("FileType", {
    pattern = { "cpp", "h" },
    callback = function()
        vim.keymap.set("n", "<leader>c", ":e %<.cpp<CR>")
        vim.keymap.set("n", "<leader>C", ":vnew %<.cpp<CR>")
        vim.keymap.set("n", "<leader>h", ":e %<.h<CR>")
        vim.keymap.set("n", "<leader>H", ":vnew %<.h<CR>")
        vim.keymap.set("n", "<leader>b", ":vnew %:p:h/CMakeLists.txt<CR>")
        vim.opt.tabstop = 4
        vim.opt.shiftwidth = 4
    end,
    group = augroup
})

