local on_attach = function(_, bufnr)
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
    local buf = vim.lsp.buf;

    vim.keymap.set('n', 'gd', buf.definition)
    vim.keymap.set('n', 'gD', buf.declaration)
    vim.keymap.set('n', 'gt', buf.type_definition)
    vim.keymap.set('n', 'gr', buf.references)
    vim.keymap.set('n', 'gR', buf.rename)
    vim.keymap.set('n', 'ga', ':CodeActionMenu<CR>')
    vim.keymap.set('n', 'gk', buf.hover)
    vim.keymap.set('n', 'gs', buf.signature_help)
    vim.keymap.set('n', '<leader><leader>', buf.formatting_sync)

    vim.keymap.set('n', 'ge', vim.diagnostic.open_float)
    vim.keymap.set('n', 'gn', vim.diagnostic.goto_next)
    vim.keymap.set('n', 'gp', vim.diagnostic.goto_prev)
end

local cmp = require('cmp')
cmp.setup({
    snippet = {
        expand = function(args)
            require('luasnip').lsp_expand(args.body) -- For `luasnip` users.
        end,
    },
    window = {
        completion = cmp.config.window.bordered(),
        documentation = cmp.config.window.bordered(),
    },
    mapping = cmp.mapping.preset.insert({
        ['<C-b>'] = cmp.mapping.scroll_docs(-4),
        ['<C-f>'] = cmp.mapping.scroll_docs(4),
        ['<C-Space>'] = cmp.mapping.complete(),
        ['<C-e>'] = cmp.mapping.abort(),
        ['<CR>'] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
    }),
    sources = cmp.config.sources({
        { name = 'nvim_lsp' },
        { name = 'luasnip' }, -- For luasnip users.
    }, {
        { name = 'buffer' },
    })
})

local capabilities = require('cmp_nvim_lsp').default_capabilities()

local lspconfig = require('lspconfig')

lspconfig.gopls.setup {
    on_attach = on_attach,
    capabilities = capabilities,
}

lspconfig.pyright.setup {
    on_attach = on_attach,
    capabilities = capabilities,
}

lspconfig.rust_analyzer.setup {
    on_attach = on_attach,
    capabilities = capabilities,
}

lspconfig.dartls.setup {
    on_attach = on_attach,
    capabilities = capabilities,
}

lspconfig.sumneko_lua.setup {
    on_attach = on_attach,
    capabilities = capabilities,
    settings = {
        -- Get the language server to recognize the `vim` global
        Lua = {
            diagnostics = {
                globals = { 'vim' },
            },
            workspace = {
                library = vim.api.nvim_get_runtime_file("", true),
            },
            telemetry = {
                enable = false,
            },
        },
    },
}

lspconfig.clangd.setup {
    on_attach = on_attach,
    capabilities = capabilities,
    cmd = {
        "clangd",
        "--resource-dir=/opt/bb/lib/llvm-14.0/lib64/clang/14.0.6/"
    }
}

lspconfig.tsserver.setup{
    on_attach = on_attach,
    capabilities = capabilities,
}
