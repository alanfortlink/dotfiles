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
          local utils = require("utils")

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
              -- diagnostics = { disable = { 'missing-fields' } },
            },
          },
        },
      }

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

  {
    'habamax/vim-godot',
    event = 'VimEnter',
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
        config = function()
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
          ['<C-y>'] = cmp.mapping.complete {},

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
            else
              -- confirm codium suggestions
              cmp.confirm { select = true }
            end
          end, { 'i', 's' }),
          ['<S-Tab>'] = cmp.mapping(function()
            if luasnip.locally_jumpable(-1) then
              luasnip.jump(-1)
            end
          end, { 'i', 's' }),
        },
        sources = {
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          -- { name = 'copilot' },
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
      indent = { enable = true, disable = { 'ruby', 'gd', 'gdscript' } },
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
      vim.keymap.set("n", "gS", function() t.lsp_workspace_symbols({ query = "" }) end, { noremap = true })
    end,
    dependencies = { 'nvim-lua/plenary.nvim', },
  },


  { "tommcdo/vim-exchange",  lazy = false },
  { "tpope/vim-surround",    lazy = false },
  {
    "mbbill/undotree",
    lazy = false,
    keys = {
      { "<localleader>u", "<cmd>UndotreeShow<CR><cmd>UndotreeFocus<CR>", desc = "UndoTree Open and Focus" },
      { "<localleader>U", "<cmd>UndotreeHide<CR>",                       desc = "UndoTree Hide" },
    },
  },
  { "tpope/vim-eunuch",         lazy = false }, -- Rename, Move, CFind
  { "farmergreg/vim-lastplace", lazy = false },
  {
    "ThePrimeagen/harpoon",
    lazy = false,
    config = function()
      require("harpoon").setup({})

      local mark = require("harpoon.mark")
      local ui = require("harpoon.ui")

      vim.keymap.set("n", "<localleader>s", mark.add_file, { noremap = true })
      vim.keymap.set("n", "<localleader>r", mark.rm_file, { noremap = true })
      vim.keymap.set("n", "<localleader>a", ui.toggle_quick_menu, { noremap = true })

      vim.keymap.set("n", "<localleader>n", ui.nav_next, { noremap = true })
      vim.keymap.set("n", "<localleader>p", ui.nav_prev, { noremap = true })

      for i = 1, 9 do vim.keymap.set("n", "<localleader>" .. i, function() ui.nav_file(i) end, { noremap = true }) end
    end,
  },
  {
    "airblade/vim-gitgutter",
    lazy = false,
    keys = {
      { "gh", "<cmd>GitGutterNextHunk<CR>", desc = "Next GitGutter Hunk" },
      { "gH", "<cmd>GitGutterPrevHunk<CR>", desc = "Previous GitGutter Hunk" },
    },
  },
  {
    "navarasu/onedark.nvim",
    priority = 1000,
    config = function()
      require('onedark').setup {
        -- Main options --
        style = 'deep',               -- Default theme style. Choose between 'dark', 'darker', 'cool', 'deep', 'warm', 'warmer' and 'light'
        transparent = false,          -- Show/hide background
        term_colors = true,           -- Change terminal color as per the selected theme style
        ending_tildes = false,        -- Show the end-of-buffer tildes. By default they are hidden
        cmp_itemkind_reverse = false, -- reverse item kind highlights in cmp menu

        -- toggle theme style ---
        toggle_style_key = nil,                                                              -- keybind to toggle theme style. Leave it nil to disable it, or set it to a string, for example "<leader>ts"
        toggle_style_list = { 'dark', 'darker', 'cool', 'deep', 'warm', 'warmer', 'light' }, -- List of styles to toggle between

        -- Change code style ---
        -- Options are italic, bold, underline, none
        -- You can configure multiple style with comma separated, For e.g., keywords = 'italic,bold'
        code_style = {
          comments = 'italic',
          keywords = 'none',
          functions = 'none',
          strings = 'none',
          variables = 'none'
        },

        -- Lualine options --
        lualine = {
          transparent = false, -- lualine center bar transparency
        },

        -- Custom Highlights --
        colors = {},     -- Override default colors
        highlights = {}, -- Override highlight groups

        -- Plugins Config --
        diagnostics = {
          darker = true,     -- darker colors for diagnostic
          undercurl = true,  -- use undercurl instead of underline for diagnostics
          background = true, -- use background color for virtual text
        },
      }

      vim.cmd.colorscheme "onedark"

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
          prefix = "// ",        -- character to use for close tag e.g. > Widget
          enabled = true         -- set to false to disable
        },
        dev_log = {
          enabled = true,
          open_cmd = "vnew", -- command to use to open the log buffer
        },
        dev_tools = {
          autostart = true,          -- autostart devtools server if not detected
          auto_open_browser = false, -- Automatically opens devtools in the browser
        },
        outline = {
          open_cmd = "30vnew", -- command to use to open the outline buffer
          auto_open = false    -- if true this will open the outline automatically when it is first populated
        },
      }
    end,
  },

  -- {
  --   "zbirenbaum/copilot.lua",
  --   config = function()
  --     require("copilot").setup({
  --       panel = {
  --         enabled = true,
  --         auto_refresh = false,
  --         keymap = {
  --           jump_prev = "[[",
  --           jump_next = "]]",
  --           accept = "<Tab>",
  --           refresh = "gr",
  --           open = "<M-CR>"
  --         },
  --         layout = {
  --           position = "bottom", -- | top | left | right
  --           ratio = 0.4
  --         },
  --       },
  --       suggestion = {
  --         enabled = true,
  --         auto_trigger = true,
  --         debounce = 75,
  --         keymap = {
  --           accept = "<Tab>",
  --           accept_word = false,
  --           accept_line = false,
  --           next = "<C-h>",
  --           prev = "<C-l>",
  --           dismiss = "<C-]>",
  --         },
  --       },
  --       filetypes = {
  --         yaml = false,
  --         markdown = false,
  --         help = false,
  --         gitcommit = false,
  --         gitrebase = false,
  --         hgcommit = false,
  --         svn = false,
  --         cvs = false,
  --         ["."] = false,
  --       },
  --       copilot_node_command = 'node', -- Node.js version must be > 18.x
  --       server_opts_overrides = {},
  --     })
  --   end,
  -- },

  -- {
  --   "zbirenbaum/copilot-cmp",
  --   config = function()
  --     require("copilot_cmp").setup()
  --   end
  -- },

  {
    "karb94/neoscroll.nvim",
    config = function()
      require('neoscroll').setup {
        easing_function = "quadratic",
      }
    end
  },

  {
    'nvim-telescope/telescope-ui-select.nvim',
    config = function()
      require("telescope").setup {
        extensions = {
          ["ui-select"] = {
            require("telescope.themes").get_dropdown {
              -- even more opts
            }

            -- pseudo code / specification for writing custom displays, like the one
            -- for "codeactions"
            -- specific_opts = {
            --   [kind] = {
            --     make_indexed = function(items) -> indexed_items, width,
            --     make_displayer = function(widths) -> displayer
            --     make_display = function(displayer) -> function(e)
            --     make_ordinal = function(e) -> string
            --   },
            --   -- for example to disable the custom builtin "codeactions" display
            --      do the following
            --   codeactions = false,
            -- }
          }
        }
      }
      -- To get ui-select loaded and working with telescope, you need to call
      -- load_extension, somewhere after setup function:
      require("telescope").load_extension("ui-select")
    end
  },

  {
    'mfussenegger/nvim-dap',
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "theHamsta/nvim-dap-virtual-text",
      "nvim-neotest/nvim-nio",
      "jay-babu/mason-nvim-dap.nvim",
    },
    config = function()
      local dap = require "dap"
      local ui = require "dapui"

      require("dapui").setup()
      require("nvim-dap-virtual-text").setup()

      require("mason-nvim-dap").setup()

      dap.adapters.python = {
        type = 'executable',
        command = 'python3',
        args = { '-m', 'debugpy.adapter' },
      }

      dap.configurations.python = {
        {
          type = 'python',
          request = 'launch',
          name = 'Launch file',
          program = '${file}',
          pythonPath = function()
            return 'python3' -- Adjust this to your Python path
          end,
        },
      }

      dap.adapters.gdb = {
        type = "executable",
        command = "gdb",
        args = { "--interpreter=dap", "--eval-command", "set print pretty on" }
      };

      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        executable = {
          command = "codelldb",
          args = { "--port", "${port}" },
        },
      };

      dap.configurations.cpp = {
        {
          name = "Attach",
          type = "codelldb",
          request = "attach",
          program = function() return require("dap.utils").pick_file({}) end,
          pid = require("dap.utils").pick_process,
          cwd = '${workspaceFolder}'
        },
        {
          name = "Launch",
          type = "codelldb",
          request = "launch",
          program = function() return require("dap.utils").pick_file({}) end,
          cwd = '${workspaceFolder}'
        },
      };


      -- dap adapter for c++ setup
      vim.keymap.set("n", "<localleader>b", dap.toggle_breakpoint)
      vim.keymap.set("n", "<localleader>dc", dap.continue)

      vim.keymap.set("n", "<localleader>dt", ui.toggle)

      vim.keymap.set("n", "<localleader>?", function()
        require("dapui").eval(nil, { enter = true })
      end)

      vim.keymap.set("n", "<F5>", dap.continue)
      vim.keymap.set("n", "<F6>", dap.step_over)
      vim.keymap.set("n", "<F7>", dap.step_into)
      vim.keymap.set("n", "<F8>", dap.step_out)
      vim.keymap.set("n", "<F9>", dap.step_back)
      vim.keymap.set("n", "<F10>", dap.restart)

      dap.listeners.before.attach.dapui_config = function()
        ui.open()
      end

      dap.listeners.before.launch.dapui_config = function()
        ui.open()
      end

      dap.listeners.before.event_terminated.dapui_config = function()
        ui.open()
      end

      dap.listeners.before.event_exited.dapui_config = function()
        ui.open()
      end
    end
  },

  {
    'stevearc/oil.nvim',
    opts = {},
    -- Optional dependencies
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("oil").setup()
    end,
  },


}, {
  ui = {
    -- If you are using a Nerd Font: set icons to an empty table which will use the
    -- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },

})

return {}
