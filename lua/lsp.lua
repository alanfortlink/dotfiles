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

vim.opt.signcolumn = 'yes' -- Reserve space for diagnostic icons

local lsp = require('lsp-zero')
lsp.preset('recommended')

lsp.ensure_installed({
  'tsserver',
  'eslint',
  'sumneko_lua',
  'clangd',
  'rust_analyzer',
})

lsp.configure('dartls', {force_setup = true, on_attach = on_attach})

lsp.nvim_workspace()
lsp.on_attach(on_attach)

lsp.setup()
