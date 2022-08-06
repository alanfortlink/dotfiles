local nmap = require('utils').nmap
local imap = require('utils').imap

local on_attach = function(_, bufnr)
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
  -- vim.cmd("set completeopt=menu,menuone,noselect")
  local buf = vim.lsp.buf;

  nmap('gd', buf.definition)
  nmap('gD', buf.declaration)
  nmap('gt', buf.type_definition)
  nmap('gr', buf.references)
  nmap('gR', buf.rename)
  nmap('gi', buf.implementation)
  nmap('ga', ':CodeActionMenu<CR>')
  nmap('gk', buf.hover)
  -- nmap('ga', buf.range_code_action)

  imap('<C-k>', buf.hover);

  nmap('ge', vim.diagnostic.open_float)
  nmap('gn', vim.diagnostic.goto_next)
  nmap('gp', vim.diagnostic.goto_prev)
  nmap('<leader>d', vim.diagnostic.setloclist)
end

local cmp = require('cmp')

-- TODO: Copied from README.md of nvim-cmp. What can I remove?
cmp.setup({
snippet = {
  -- REQUIRED - you must specify a snippet engine
  expand = function(args)
    require('luasnip').lsp_expand(args.body) -- For `luasnip` users.
    -- vim.fn["vsnip#anonymous"](args.body) -- For `vsnip` users.
    -- require('snippy').expand_snippet(args.body) -- For `snippy` users.
    -- vim.fn["UltiSnips#Anon"](args.body) -- For `ultisnips` users.
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
  -- { name = 'vsnip' }, -- For vsnip users.
  -- { name = 'ultisnips' }, -- For ultisnips users.
  -- { name = 'snippy' }, -- For snippy users.
}, {
  { name = 'buffer' },
})
})

local capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())
-- local capabilities = vim.lsp.protocol.make_client_capabilities()

local lspconfig = require('lspconfig')

lspconfig.gopls.setup{
  on_attach = on_attach,
  capabilities = capabilities,
}

lspconfig.rust_analyzer.setup{
  on_attach = on_attach,
  capabilities = capabilities,
}

lspconfig.dartls.setup{
  on_attach = on_attach,
  capabilities = capabilities,
}

lspconfig.sumneko_lua.setup{
  on_attach = on_attach,
  capabilities = capabilities,
  settings = {
    -- Get the language server to recognize the `vim` global
    Lua = {
      diagnostics = {
        globals = {'vim'},
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

lspconfig.clangd.setup{
  on_attach = on_attach,
  capabilities = capabilities,
  cmd = {
    "clangd",
    "--resource-dir=/opt/bb/lib/llvm-12.0/lib64/clang/12.0.1/"
  }
}
