local augroup = vim.api.nvim_create_augroup("augroup", { clear = true })
local utils = require('utils')

-- Flutter build / run shortcuts
vim.api.nvim_create_autocmd("FileType", {
    pattern = { "dart" },
    callback = function()
        vim.keymap.set('n', '<F4>', ':FlutterDevices<CR>')
        vim.keymap.set('n', '<F5>', ':FlutterRun<CR>')
        vim.keymap.set('n', '<F6>', ':FlutterVSplit<CR>')
        vim.keymap.set('n', '<F7>', ':FlutterHotRestart<CR>')
        vim.keymap.set('n', '<F8>', ':FlutterQuit<CR>')
    end,
    group = augroup
})

-- Update git gutter on save
vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = { "*" },
    callback = function()
        vim.cmd('GitGutter')
    end,
    group = augroup
})

-- Jump between .h/.cpp and go to local CMakeLists.txt
vim.api.nvim_create_autocmd("FileType", {
    pattern = { "cpp", "h" },
    callback = function()
        vim.keymap.set('n', '<leader>c', ':e %<.cpp<CR>')
        vim.keymap.set('n', '<leader>C', ':vnew %<.cpp<CR>')
        vim.keymap.set('n', '<leader>h', ':e %<.h<CR>')
        vim.keymap.set('n', '<leader>H', ':vnew %<.h<CR>')
        vim.keymap.set('n', '<leader>b', ':vnew %:p:h/CMakeLists.txt<CR>')
    end,
    group = augroup
})

-- Auto-scroll quickfix
vim.api.nvim_create_autocmd("QuickFixCmdPost", {
    pattern = { "*" },
    callback = function()
        local quickfix_bufnr = utils.get_quickfix_bufnr();
        if quickfix_bufnr >= 0 then
            vim.api.nvim_buf_call(quickfix_bufnr, function() vim.cmd([[normal G]]) end)
        end
    end,
    group = augroup
})

