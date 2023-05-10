local  cfg = {
  debug = false, -- set to true to enable debug logging
  log_path = vim.fn.stdpath("cache") .. "/lsp_signature.log", -- log dir when debug is on
  verbose = false, -- show debug line number

  bind = true, -- This is mandatory, otherwise border config won't get registered.
               -- If you want to hook lspsaga or other signature handler, pls set to false
  doc_lines = 10, -- will show two lines of comment/doc(if there are more than two lines in doc, will be truncated);
                 -- set to 0 if you DO NOT want any API comments be shown
                 -- This setting only take effect in insert mode, it does not affect signature help in normal
                 -- mode, 10 by default

  max_height = 12, -- max height of signature floating_window
  max_width = 80, -- max_width of signature floating_window
  noice = false, -- set to true if you using noice to render markdown
  wrap = true, -- allow doc/signature text wrap inside floating_window, useful if your lsp return doc/sig is too long
  
  floating_window = false, -- show hint in a floating window, set to false for virtual text only mode

  floating_window_above_cur_line = true, -- try to place the floating above the current line when possible Note:
  -- will set to true when fully tested, set to false will use whichever side has more space
  -- this setting will be helpful if you do not want the PUM and floating win overlap

  floating_window_off_x = 1, -- adjust float windows x position. 
                             -- can be either a number or function
  floating_window_off_y = 0, -- adjust float windows y position. e.g -2 move window up 2 lines; 2 move down 2 lines
                              -- can be either number or function, see examples

  close_timeout = 4000, -- close floating window after ms when laster parameter is entered
  fix_pos = false,  -- set to true, the floating window will not auto-close until finish all parameters
  hint_prefix = "",  -- Panda for parameter, NOTE: for the terminal not support emoji, might crash
  hint_scheme = "String",
  hi_parameter = "LspSignatureActiveParameter", -- how your parameter will be highlight
  handler_opts = {
    border = "rounded"   -- double, rounded, single, shadow, none, or a table of borders
  },

  always_trigger = false, -- sometime show signature on new line or in middle of parameter can be confusing, set it to false for #58

  auto_close_after = nil, -- autoclose signature float win after x sec, disabled if nil.
  extra_trigger_chars = {}, -- Array of extra characters that will trigger signature completion, e.g., {"(", ","}
  zindex = 200, -- by default it will be on top of all floating windows, set to <= 50 send it to bottom

  padding = '', -- character to pad on left and right of signature can be ' ', or '|'  etc

  transparency = nil, -- disabled by default, allow floating win transparent value 1~100
  shadow_blend = 36, -- if you using shadow as border use this set the opacity
  shadow_guibg = 'Black', -- if you using shadow as border use this set the color e.g. 'Green' or '#121315'
  timer_interval = 200, -- default timer check interval set to lower value if you want to reduce latency
  toggle_key = nil, -- toggle signature on and off in insert mode,  e.g. toggle_key = '<M-x>'
  toggle_key_flip_floatwin_setting = false, -- true: toggle float setting after toggle key pressed

  select_signature_key = nil, -- cycle to next signature, e.g. '<M-n>' function overloading
  move_cursor_key = nil, -- imap, use nvim_set_current_win to move cursor between current win and floating
}

require'lsp_signature'.setup(cfg) -- no need to specify bufnr if you don't use toggle_key

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
  ["<CR>"] = cmp.mapping.confirm({ select = true }),     -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
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
