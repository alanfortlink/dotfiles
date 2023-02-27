local on_attach = function(_, bufnr)
  local buf = vim.lsp.buf;

  vim.keymap.set("n", "gd", buf.definition, { noremap = true })
  vim.keymap.set("n", "gD", buf.declaration, { noremap = true })
  vim.keymap.set("n", "gt", buf.type_definition, { noremap = true })
  vim.keymap.set("n", "gr", buf.references, { noremap = true })
  vim.keymap.set("n", "gR", buf.rename, { noremap = true })
  vim.keymap.set("n", "ga", buf.code_action, { noremap = true })
  vim.keymap.set("n", "gk", buf.hover, { noremap = true })
  vim.keymap.set("n", "gs", buf.signature_help, { noremap = true })
  vim.keymap.set("n", "<leader><leader>", buf.format, { noremap = true })

  vim.keymap.set("n", "ge", vim.diagnostic.open_float, { noremap = true })
  vim.keymap.set("n", "gn", vim.diagnostic.goto_next, { noremap = true })
  vim.keymap.set("n", "gp", vim.diagnostic.goto_prev, { noremap = true })
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
    { name = "snipmate" },
    { name = "neorg" },
  }
})

lsp.ensure_installed({
  "clangd",
})

lsp.configure("dartls", { force_setup = true, on_attach = on_attach })
lsp.on_attach(on_attach)

lsp.nvim_workspace()
lsp.setup()

local lspconfig = require("lspconfig")
lspconfig.clangd.setup {
    on_attach = on_attach,
    capabilities = capabilities,
    cmd = {
        "clangd",
        "--resource-dir=/opt/bb/lib/llvm-15.0/lib64/clang/15.0.7/"
    }
}
