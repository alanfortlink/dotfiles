local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  'tpope/vim-sleuth', -- Detect tabstop and shiftwidth automatically
  { 'numToStr/Comment.nvim', opts = {} },
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

            vim.keymap.set("n", "gr", buf.references, { noremap = true })
            vim.keymap.set("n", "gR", buf.rename, { noremap = true })

            vim.keymap.set("n", "gd", require('telescope.builtin').lsp_definitions, { noremap = true })
            vim.keymap.set("n", "gD", buf.declaration, { noremap = true })

            vim.keymap.set("n", "ga", buf.code_action, { noremap = true })
            vim.keymap.set("n", "K", buf.hover, { noremap = true })
            vim.keymap.set("n", "gs", buf.signature_help, { noremap = true })

            vim.keymap.set("n", "<leader><leader>", buf.format, { noremap = true })

            vim.keymap.set("n", "gn", vim.diagnostic.goto_next, { noremap = true })
            vim.keymap.set("n", "gp", vim.diagnostic.goto_prev, { noremap = true })
            vim.keymap.set("n", "ge", vim.diagnostic.open_float, { noremap = true })
  
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
                -- diagnostics = { disable = { 'missing-fields' } },
              },
            },
          },
        }
  
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
              -- This handles overriding only values explicitly passed
              -- by the server configuration above. Useful when disabling
              -- certain features of an LSP (for example, turning off formatting for tsserver)
              server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
              require('lspconfig')[server_name].setup(server)
            end,
          },
        }
      end,
    },
{ -- Autocompletion
    'hrsh7th/nvim-cmp',
    event = 'InsertEnter',
    dependencies = {
      -- Snippet Engine & its associated nvim-cmp source
      {
        'L3MON4D3/LuaSnip',
        build = (function()
          -- Build Step is needed for regex support in snippets.
          -- This step is not supported in many windows environments.
          -- Remove the below condition to re-enable on windows.
          if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
            return
          end
          return 'make install_jsregexp'
        end)(),
	config = function ()
	      require("luasnip.loaders.from_snipmate").lazy_load()
	end,
      },
      'saadparwaiz1/cmp_luasnip',
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-path',
    },
    config = function()
      -- See `:help cmp`
      local cmp = require 'cmp'
      local luasnip = require 'luasnip'
      luasnip.config.setup {}

      cmp.setup {
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        completion = { completeopt = 'menu,menuone,noinsert' },

        mapping = cmp.mapping.preset.insert {
          -- Select the [n]ext item
          ['<C-n>'] = cmp.mapping.select_next_item(),
          -- Select the [p]revious item
          ['<C-p>'] = cmp.mapping.select_prev_item(),

          -- Scroll the documentation window [b]ack / [f]orward
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),

          -- Accept ([y]es) the completion.
          --  This will auto-import if your LSP supports it.
          --  This will expand snippets if the LSP sent a snippet.
          ['<CR>'] = cmp.mapping.confirm { select = true },

          -- Manually trigger a completion from nvim-cmp.
          --  Generally you don't need this, because nvim-cmp will display
          --  completions whenever it has completion options available.
          ['<C-Space>'] = cmp.mapping.complete {},

          -- Think of <c-l> as moving to the right of your snippet expansion.
          --  So if you have a snippet that's like:
          --  function $name($args)
          --    $body
          --  end
          --
          -- <c-l> will move you to the right of each of the expansion locations.
          -- <c-h> is similar, except moving you backwards.
          ['<Tab>'] = cmp.mapping(function()
            if luasnip.expand_or_locally_jumpable() then
              luasnip.expand_or_jump()
            end
          end, { 'i', 's' }),
          ['<S-Tab>'] = cmp.mapping(function()
            if luasnip.locally_jumpable(-1) then
              luasnip.jump(-1)
            end
          end, { 'i', 's' }),

          -- For more advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
          --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps
        },
        sources = {
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          { name = 'path' },
        },
      }
    end,
  },

  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    opts = {
      ensure_installed = {},
      auto_install = true,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = { 'ruby' },
      },
      indent = { enable = true, disable = { 'ruby' } },
    },
    config = function(_, opts)
      ---@diagnostic disable-next-line: missing-fields
      require('nvim-treesitter.configs').setup(opts)
    end,
  },

  {
    'nvim-telescope/telescope.nvim', 
    lazy = false,
    config = function() 

      require("telescope").setup({
        defaults = {
          file_ignore_patterns = {
            "^./build/",
            "^./android/",
            "^./macos/",
            "^./ios/",
            "^./web/",
            "^./linux/",
            "^./windows/",
          },
	  mappings = {
		  i = { ['<c-enter>'] = 'to_fuzzy_refine' },
	  },
        },
      })

      local t = require("telescope.builtin")

      -- Find files
      vim.keymap.set("n", "<leader>f", function() t.find_files({ hidden = false }) end, { noremap = true })

      -- Find with hidden files
      vim.keymap.set("n", "<leader>F", function() t.find_files({ hidden = true }) end, { noremap = true })

      -- Commands
      vim.keymap.set("n", "<localleader>c", t.commands, { noremap = true })
      vim.keymap.set("n", "<localleader>h", t.help_tags, { noremap = true })

      -- Almighty GREP
      vim.keymap.set("n", "<leader>g", t.live_grep, { noremap = true })
      vim.keymap.set("v", "<leader>g", t.grep_string, { noremap = true })

      -- Other telescope stuff
      vim.keymap.set("n", "<localleader><localleader>", t.resume, { noremap = true })
      vim.keymap.set("n", "<leader><localleader>", t.builtin, { noremap = true })

      vim.keymap.set("n", "gs", t.lsp_document_symbols, { noremap = true })
      vim.keymap.set("n", "gS", function() t.lsp_workspace_symbols({query = ""}) end, { noremap = true })
    end,
    dependencies = { 'nvim-lua/plenary.nvim', },
  },


  { "tommcdo/vim-exchange", lazy = false },
  { "tpope/vim-surround", lazy = false },
  { 
    "mbbill/undotree", 
    lazy = false,
    keys = {
      { "<localleader>u", "<cmd>UndotreeShow<CR><cmd>UndotreeFocus<CR>", desc = "UndoTree Open and Focus"},
      { "<localleader>U", "<cmd>UndotreeHide<CR>", desc = "UndoTree Hide"},
    },
  },
  { "tpope/vim-eunuch", lazy = false },      -- Rename, Move, CFind
  { "farmergreg/vim-lastplace", lazy = false },
  { 
    "ThePrimeagen/harpoon", 
    lazy = false, 
    config = function()
      require("harpoon").setup({})

      local mark = require("harpoon.mark")
      local ui = require("harpoon.ui")

      vim.keymap.set("n", "<localleader>s", mark.add_file, { noremap = true})
      vim.keymap.set("n", "<localleader>r", mark.rm_file, { noremap = true})
      vim.keymap.set("n", "<localleader>a", ui.toggle_quick_menu, { noremap = true})

      vim.keymap.set("n", "<localleader>n", ui.nav_next, { noremap = true})
      vim.keymap.set("n", "<localleader>p", ui.nav_prev, { noremap = true})

      for i = 1, 9 do vim.keymap.set("n", "<localleader>" .. i, function() ui.nav_file(i) end, { noremap = true}) end
    end, 
  },
  { 
    "airblade/vim-gitgutter", 
    lazy = false,
    keys = {
      { "gh", "<cmd>GitGutterNextHunk<CR>", desc = "Next GitGutter Hunk"},
      { "gH", "<cmd>GitGutterPrevHunk<CR>", desc = "Previous GitGutter Hunk"},
    },
  },

  {
    "navarasu/onedark.nvim",
    config = function()
      require('onedark').load()
      require('onedark').setup {
          style = 'deep'
      }

      if not pcall(function() vim.cmd.colorscheme("onedark") end) then
      end
      vim.cmd("highlight WinSeparator guibg=DarkGray")
      vim.cmd("highlight WinSeparator guibg=DarkGray")
      vim.cmd("hi NormalNC guibg=NONE ctermbg=NONE")
      vim.cmd("hi Normal guibg=NONE ctermbg=NONE")
      vim.cmd("hi EndOfBuffer guibg=NONE ctermbg=NONE")
    end,
  },
  { 
    "akinsho/flutter-tools.nvim", 
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function() 
      require("flutter-tools").setup {
        decorations = {
          statusline = {
            -- set to true to be able use the 'flutter_tools_decorations.app_version' in your statusline
            -- this will show the current version of the flutter app from the pubspec.yaml file
            app_version = true,
            -- set to true to be able use the 'flutter_tools_decorations.device' in your statusline
            -- this will show the currently running device if an application was started with a specific
            -- device
            device = true,
          }
        },
        closing_tags = {
          highlight = "Comment", -- highlight for the closing tag
          prefix = "// ", -- character to use for close tag e.g. > Widget
          enabled = true -- set to false to disable
        },
        dev_log = {
          enabled = true,
          open_cmd = "vnew", -- command to use to open the log buffer
        },
        dev_tools = {
          autostart = true, -- autostart devtools server if not detected
          auto_open_browser = false, -- Automatically opens devtools in the browser
        },
        outline = {
          open_cmd = "30vnew", -- command to use to open the outline buffer
          auto_open = false -- if true this will open the outline automatically when it is first populated
        },
      }
    end,
  },
  { 
    'github/copilot.vim',
    config = function() end,
  },

  })

return {}
