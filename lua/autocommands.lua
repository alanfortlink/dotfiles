local augroup = vim.api.nvim_create_augroup("augroup", { clear = true })
local utils = require('utils')
local nmap = utils.nmap

-- Flutter build / run shortcuts
vim.api.nvim_create_autocmd("FileType", {
    pattern = { "dart" },
    callback = function()
        nmap('<F4>', ':FlutterDevices<CR>')
        nmap('<F5>', ':FlutterRun<CR>')
        nmap('<F6>', ':FlutterVSplit<CR>')
        nmap('<F7>', ':FlutterHotRestart<CR>')
        nmap('<F8>', ':FlutterQuit<CR>')
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
        nmap('<leader>c', ':e %<.cpp<CR>')
        nmap('<leader>C', ':vnew %<.cpp<CR>')
        nmap('<leader>h', ':e %<.h<CR>')
        nmap('<leader>H', ':vnew %<.h<CR>')
        nmap('<leader>b', ':vnew %:p:h/CMakeLists.txt<CR>')
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

