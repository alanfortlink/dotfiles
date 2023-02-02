local utils = require("utils")

local augroup = vim.api.nvim_create_augroup("autocommandsaugroup", { clear = true })

-- Update git gutter on save
vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = { "*" },
    callback = function()
        vim.cmd("GitGutter")
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

