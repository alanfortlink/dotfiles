require("luasnip.loaders.from_snipmate").lazy_load()

local luasnip = require("luasnip")
vim.keymap.set("i", "<Tab>", function()
    if luasnip.expand_or_jumpable() then
        luasnip.expand_or_jump()
    else
        vim.api.nvim_command("normal! a\t")
    end
end)

local function wrap_jump(value)
    return function()
        luasnip.jump(value)
    end
end

vim.keymap.set("i", "<S-Tab>", wrap_jump(-1))
vim.keymap.set("s", "<S-Tab>", wrap_jump(-1))

vim.keymap.set("s", "<Tab>", wrap_jump(1))
