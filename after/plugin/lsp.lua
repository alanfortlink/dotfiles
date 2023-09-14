local _wrap_in = function(widget, buf)
  local seen = false
  buf.code_action({
    filter = function(ca)
      -- P(ca.command.arguments[1].action)

      if seen then
        return false
      end

      if ca.command.arguments[1].action == "dart.assist.flutter.wrap."..widget then
       seen = true
       return true
      end
    end,
    apply = true,
  })
end

local _wrap_in_wrapper = function(widget, buf)
  return function()
    _wrap_in(widget, buf)
  end
end

local on_attach = function(_, bufnr)
  local buf = vim.lsp.buf;
  vim.opt.completeopt = { "menu", "menuone", "noinsert" }
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

  vim.keymap.set("n", "gwc", _wrap_in_wrapper("container", buf), { noremap = true })
  vim.keymap.set("n", "gwC", _wrap_in_wrapper("column", buf), { noremap = true })
  vim.keymap.set("n", "gwr", _wrap_in_wrapper("row", buf), { noremap = true })
  vim.keymap.set("n", "gwR", _wrap_in_wrapper("removeWidget", buf), { noremap = true })
  vim.keymap.set("n", "gww", _wrap_in_wrapper("generic", buf), { noremap = true })
end

local lsp = require("lsp-zero")
lsp.preset("recommended")

local cmp = require("cmp")

local capabilities = {
  textDocument = {
    completion = {
      completionItem = {
        detail = true,
        placeholder = true,
      }
    }
  }
}

local cmp_mappings = lsp.defaults.cmp_mappings({
  ["<C-b>"] = cmp.mapping.scroll_docs(-4),
  ["<C-f>"] = cmp.mapping.scroll_docs(4),
  ["<C-Space>"] = cmp.mapping.complete(),
  ["<C-Y>"] = cmp.mapping.complete(),
  ["<C-e>"] = cmp.mapping.abort(),
  ["<CR>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
})

cmp_mappings["<Tab>"] = nil
cmp_mappings["<S-Tab>"] = nil

lsp.setup_nvim_cmp({
  completion = {
  },
  mapping = cmp_mappings,
  window = {
    completion = cmp.config.window.bordered(),
  },
  sources = {
    { name = "nvim_lsp" },
    { name = "path" },
    { name = "buffer" },
    { name = "neorg" },
  }
})

lsp.ensure_installed({
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

vim.diagnostic.config({ virtual_text = true, update_in_insert = false })

-- -- Customize diagnostic display
-- vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
--   vim.lsp.diagnostic.on_publish_diagnostics, {
--     -- Disable virtual_text
--     virtual_text = false,
--     -- Keep the sign column
--     signs = true,
--     -- Show diagnostics in status line
--     update_in_insert = false,
--   }
-- )
