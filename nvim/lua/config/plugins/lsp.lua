return {
  { -- LSP Configuration & Plugins
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Automatically install LSPs and related tools to stdpath for Neovim
      'williamboman/mason.nvim',
      'williamboman/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',

      -- Useful status updates for LSP.
      -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
      { 'j-hui/fidget.nvim', opts = {} },

      -- `neodev` configures Lua LSP for your Neovim config, runtime and plugins
      -- used for completion, annotations and signatures of Neovim apis
      { 'folke/neodev.nvim', opts = {} },
    },
    config = function()
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          local buf = vim.lsp.buf;
          local utils = require("utils")

          vim.keymap.set("n", "gr", buf.references, { noremap = true })
          vim.keymap.set("n", "gR", buf.rename, { noremap = true })

          vim.keymap.set("n", "gd", buf.definition, { noremap = true })

          vim.keymap.set("n", "ga", buf.code_action, { noremap = true })
          vim.keymap.set("n", "K", buf.hover, { noremap = true })
          vim.keymap.set("n", "gs", buf.signature_help, { noremap = true })

          vim.keymap.set("n", "<leader><leader>", buf.format, { noremap = true })

          vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { noremap = true })
          vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { noremap = true })
          vim.keymap.set("n", "ge", vim.diagnostic.open_float, { noremap = true })

          vim.keymap.set("n", "gwc", utils.code_action_wrapper("container", buf), { noremap = true })
          vim.keymap.set("n", "gwC", utils.code_action_wrapper("column", buf), { noremap = true })
          vim.keymap.set("n", "gwr", utils.code_action_wrapper("row", buf), { noremap = true })
          vim.keymap.set("n", "gwR", utils.code_action_wrapper("removeWidget", buf), { noremap = true })
          vim.keymap.set("n", "gww", utils.code_action_wrapper("generic", buf), { noremap = true })

          -- The following two autocommands are used to highlight references of the
          -- word under your cursor when your cursor rests there for a little while.
          --    See `:help CursorHold` for information about when this is executed
          --
          -- When you move your cursor, the highlights will be cleared (the second autocommand).
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client.server_capabilities.documentHighlightProvider then
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              callback = vim.lsp.buf.clear_references,
            })
          end
        end,
      })

      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = vim.tbl_deep_extend('force', capabilities, require('cmp_nvim_lsp').default_capabilities())

      local servers = {
        -- clangd = {},
        lua_ls = {
          settings = {
            Lua = {
              completion = {
                callSnippet = 'Replace',
              },
              workspace = {
                library = {
                  "${3rd}/love2d/library"
                },
              },
              -- diagnostics = { disable = { 'missing-fields' } },
            },
          },
        },
      }

      require('lspconfig').clangd.setup({
        capabilities = capabilities,
        cmd = {
          -- '/usr/bin/clangd'
          -- '/opt/homebrew/Cellar/llvm/19.1.4/bin/clangd',
          '/opt/homebrew/Cellar/llvm/19.1.6/bin/clangd',
        }
      })

      require('lspconfig').gdscript.setup(capabilities)
      require('mason').setup()

      local ensure_installed = vim.tbl_keys(servers or {})
      vim.list_extend(ensure_installed, {
        'stylua', -- Used to format Lua code
      })
      require('mason-tool-installer').setup { ensure_installed = ensure_installed }

      require('mason-lspconfig').setup {
        handlers = {
          function(server_name)
            local server = servers[server_name] or {}
            server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
            require('lspconfig')[server_name].setup(server)
          end,
        },
      }
    end,
  },
}
