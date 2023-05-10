vim.cmd("packadd packer.nvim")

require("packer").startup(function(use)
  use {
    -- '/Users/alansilva/code/repos/blackjack.nvim',
    'alanfortlink/blackjack.nvim',
    requires = { 'nvim-lua/plenary.nvim' },
  }

  -- PACKER.NVIM
  use { "wbthomason/packer.nvim" }

  -- TOOLS
  use { "nvim-lua/plenary.nvim" } -- For telescope and others
  use { "mbbill/undotree" }
  use { "tpope/vim-eunuch" }      -- Rename, Move, CFind
  use { "jremmen/vim-ripgrep" }
  use { "farmergreg/vim-lastplace" }
  use { "nvim-treesitter/nvim-treesitter" }
  use { 'nvim-treesitter/nvim-treesitter-textobjects' }


  use {
    "navarasu/onedark.nvim",
    config = function()
      require('onedark').load()
    end,
  }

  use {
    "nvim-neorg/neorg",
    run = ":Neorg sync-parsers", -- This is the important bit!
    config = function()
    end,
  }

  -- FLUTTER
  -- use { "thosakwe/vim-flutter" }
  use { "akinsho/flutter-tools.nvim", requires = "nvim-lua/plenary.nvim" }

  -- NAVIGATION
  use { "scrooloose/nerdtree" }
  use { "nvim-telescope/telescope.nvim" }
  use { "ThePrimeagen/harpoon" }

  -- AUTO-COMPLETE
  use {
    "VonHeikemen/lsp-zero.nvim",
    requires = {
      -- LSP Support
      { "neovim/nvim-lspconfig" },
      { "williamboman/mason.nvim" },
      { "williamboman/mason-lspconfig.nvim" },

      -- Autocompletion
      { "hrsh7th/nvim-cmp" },
      { "hrsh7th/cmp-buffer" },
      { "hrsh7th/cmp-path" },
      { "saadparwaiz1/cmp_luasnip" },
      { "hrsh7th/cmp-nvim-lsp" },
      { "hrsh7th/cmp-nvim-lua" },

      -- Snippets
      { "L3MON4D3/LuaSnip" },
      { "rafamadriz/friendly-snippets" },
    }
  }

  -- EDIT
  use { "tommcdo/vim-exchange" }
  use { "tpope/vim-surround" }

  -- STYLE
  use { "airblade/vim-gitgutter" }
  use { "nvim-lualine/lualine.nvim" }
  use { "ggandor/leap.nvim" }

  use {
    'ldelossa/gh.nvim',
    requires = { { 'ldelossa/litee.nvim' } }
  }

  -- COLORSCHEMES
  use { "tomasiser/vim-code-dark" }
  use { "ellisonleao/gruvbox.nvim" }
  use { "folke/tokyonight.nvim" }
  use { "catppuccin/nvim" }
  use { "EdenEast/nightfox.nvim" }

  use { '1995eaton/vim-better-javascript-completion' }
  use { 'eandrju/cellular-automaton.nvim' }
  use {
    "ray-x/lsp_signature.nvim",
  }
end)
