-- Jump between .h/.cpp and go to local CMakeLists.txt
vim.keymap.set("n", "<leader>h", ":e %<.h<CR>")
vim.keymap.set("n", "<leader>H", ":vnew %<.h<CR>")
vim.keymap.set("n", "<leader>b", ":vnew %:p:h/CMakeLists.txt<CR>")
