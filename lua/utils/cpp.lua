local augroup = vim.api.nvim_create_augroup("dartaugroup", { clear = true })

-- Jump between .h/.cpp and go to local CMakeLists.txt
vim.api.nvim_create_autocmd("FileType", {
    pattern = { "cpp", "h" },
    callback = function()
        vim.keymap.set("n", "<leader>c", ":e %<.cpp<CR>")
        vim.keymap.set("n", "<leader>C", ":vnew %<.cpp<CR>")
        vim.keymap.set("n", "<leader>h", ":e %<.h<CR>")
        vim.keymap.set("n", "<leader>H", ":vnew %<.h<CR>")
        vim.keymap.set("n", "<leader>b", ":vnew %:p:h/CMakeLists.txt<CR>")
    end,
    group = augroup
})

