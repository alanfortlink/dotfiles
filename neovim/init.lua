-- Bootstrap Lazy.nvim
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

require("utils")
require("sets")
require("mappings")

require("lazy").setup({
  {
    'alanfortlink/blackjack.nvim',
    lazy = false,
    keys = {
      { "<leader>bj", "<cmd>BlackJackNewGame<CR>", desc = "BlackJack"},
    },
    dependencies = { 'nvim-lua/plenary.nvim' },
  },



  { 
    "scrooloose/nerdtree",
    lazy = false,
    keys = {
      { "<bslash><bslash>", "<cmd>NERDTreeToggle<CR>", desc = "NERDTree Toggle",}
    },
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
          layout_config = {
            vertical = {
              width = 0.8,
              height = 0.6,
            },
            horizontal = {
              width = 0.8,
              height = 0.6,
            },
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

  -- LSP
  { 
    'VonHeikemen/lsp-zero.nvim', 
    lazy = false,
    branch = 'v3.x',
    config = function() 
      local lsp_zero = require('lsp-zero')

      lsp_zero.on_attach(function(client, bufnr)
        lsp_zero.default_keymaps({buffer = bufnr})

        local buf = vim.lsp.buf;

        vim.keymap.set("n", "gR", buf.rename, { noremap = true })
        vim.keymap.set("n", "ga", buf.code_action, { noremap = true })

        vim.keymap.set("n", "ga", buf.code_action, { noremap = true })
        vim.keymap.set("n", "<leader><leader>", buf.format, { noremap = true })

        vim.keymap.set("n", "gn", vim.diagnostic.goto_next, { noremap = true })
        vim.keymap.set("n", "gp", vim.diagnostic.goto_prev, { noremap = true })
        vim.keymap.set("n", "ge", vim.diagnostic.open_float, { noremap = true })
      end)

      local cmp = require('cmp')
      local cmp_action = require('lsp-zero').cmp_action()

      cmp.setup({
        mapping = cmp.mapping.preset.insert({
          -- `Enter` key to confirm completion
          ['<CR>'] = cmp.mapping.confirm({select = false}),

          -- Ctrl+Space to trigger completion menu
          ['<C-Space>'] = cmp.mapping.complete(),

          -- Navigate between snippet placeholder
          ['<C-f>'] = cmp_action.luasnip_jump_forward(),
          ['<C-b>'] = cmp_action.luasnip_jump_backward(),

          -- Scroll up and down in the completion documentation
          ['<C-u>'] = cmp.mapping.scroll_docs(-4),
          ['<C-d>'] = cmp.mapping.scroll_docs(4),
        })
      })

      local lspconfig = require("lspconfig")
      lspconfig.clangd.setup {
        on_attach = on_attach,
        capabilities = capabilities,
        cmd = {
          "clangd",
          -- "--resource-dir=/opt/bb/lib/llvm-15.0/lib64/clang/15.0.7/"
        },
      }
    end,
    dependencies = {
      {'neovim/nvim-lspconfig'},
      {'hrsh7th/cmp-nvim-lsp'},
      {'hrsh7th/nvim-cmp'},
      {
        'L3MON4D3/LuaSnip',
        lazy = false,
        config = function()
          require("luasnip.loaders.from_snipmate").lazy_load()

          local luasnip = require("luasnip")
          vim.keymap.set("i", "<Tab>", function()
            if luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              vim.api.nvim_command("normal! a\t")
            end
          end, { noremap = true})

          local function wrap_jump(value)
            return function()
              luasnip.jump(value)
            end
          end

          vim.keymap.set("i", "<S-Tab>", wrap_jump(-1), { noremap = true})
          vim.keymap.set("s", "<S-Tab>", wrap_jump(-1), { noremap = true})

          vim.keymap.set("s", "<Tab>", wrap_jump(1), { noremap = true})
        end,
      },
    },
  },
  
  { 
    "nvim-treesitter/nvim-treesitter",
    config = function() 
      require "nvim-treesitter.configs".setup {
        -- Install parsers synchronously (only applied to `ensure_installed`)
        sync_install = false,

        -- Automatically install missing parsers when entering buffer
        -- Recommendation: set to false if you don"t have `tree-sitter` CLI installed locally
        auto_install = true,

        highlight = {
          -- `false` will disable the whole extension
          enable = true,

          -- Setting this to true will run `:h syntax` and tree-sitter at the same time.
          -- Set this to `true` if you depend on "syntax" being enabled (like for indentation).
          -- Using this option may slow down your editor, and you may see some duplicate highlights.
          -- Instead of true it can also be a list of languages
          additional_vim_regex_highlighting = false,
        },
        textsubjects = {
          enable = true,
          prev_selection = ',',     -- (Optional) keymap to select the previous selection
          keymaps = {
            ['.'] = 'textsubjects-smart',
            [';'] = 'textsubjects-container-outer',
            ['i;'] = 'textsubjects-container-inner',
          },
        },
      }
    end,
  },

  {
    "navarasu/onedark.nvim",
    config = function()
      require('onedark').load()
      if not pcall(function() vim.cmd.colorscheme("onedark") end) then
      end
      vim.cmd("highlight WinSeparator guibg=DarkGray")
      vim.cmd("highlight WinSeparator guibg=DarkGray")
      vim.cmd("hi NormalNC guibg=NONE ctermbg=NONE")
      vim.cmd("hi Normal guibg=NONE ctermbg=NONE")
      vim.cmd("hi EndOfBuffer guibg=NONE ctermbg=NONE")
    end,
  },
})
