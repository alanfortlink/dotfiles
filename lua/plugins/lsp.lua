local on_attach = function(_, bufnr)
  vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")
  local buf = vim.lsp.buf;

  vim.keymap.set("n", "gd", buf.definition)
  vim.keymap.set("n", "gD", buf.declaration)
  vim.keymap.set("n", "gt", buf.type_definition)
  vim.keymap.set("n", "gr", buf.references)
  vim.keymap.set("n", "gR", buf.rename)
  vim.keymap.set("n", "ga", buf.code_action)
  vim.keymap.set("n", "gk", buf.hover)
  vim.keymap.set("n", "gs", buf.signature_help)
  vim.keymap.set("n", "<leader><leader>", buf.format)

  vim.keymap.set("n", "ge", vim.diagnostic.open_float)
  vim.keymap.set("n", "gn", vim.diagnostic.goto_next)
  vim.keymap.set("n", "gp", vim.diagnostic.goto_prev)
end

local lsp = require("lsp-zero")
lsp.preset("recommended")

local cmp = require("cmp")
local cmp_mappings = lsp.defaults.cmp_mappings({
  ["<C-b>"] = cmp.mapping.scroll_docs(-4),
  ["<C-f>"] = cmp.mapping.scroll_docs(4),
  ["<C-Space>"] = cmp.mapping.complete(),
  ["<C-e>"] = cmp.mapping.abort(),
  ["<CR>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
})

cmp_mappings["<Tab>"] = nil
cmp_mappings["<S-Tab>"] = nil

lsp.setup_nvim_cmp({
  mapping = cmp_mappings,
  sources = {
    { name = "nvim_lsp" },
    { name = "neorg" },
  }
})

lsp.ensure_installed({
  "tsserver",
  "eslint",
  "clangd",
  "rust_analyzer",
})

lsp.configure("dartls", { force_setup = true, on_attach = on_attach })
lsp.on_attach(on_attach)

lsp.nvim_workspace()
lsp.setup()
