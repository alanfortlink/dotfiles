vim.cmd [[packadd packer.nvim]]

require("packer").startup(function()
    -- PACKER.NVIM
    use { "wbthomason/packer.nvim" }

    -- TOOLS
    use { "nvim-lua/plenary.nvim" } -- For telescope and others
    use { "tpope/vim-fugitive" }
    use { "mbbill/undotree" }
    use { "tpope/vim-eunuch" } -- Rename, Move, CFind, Move
    use { "jremmen/vim-ripgrep" }
    use { "farmergreg/vim-lastplace" }
    use { "nvim-treesitter/nvim-treesitter" }

    -- FLUTTER
    -- use { "thosakwe/vim-flutter" }
    use { "akinsho/flutter-tools.nvim", requires = "nvim-lua/plenary.nvim" }

    -- NAVIGATION
    use { "scrooloose/nerdtree" }
    use { "justinmk/vim-sneak" }
    use { "nvim-telescope/telescope.nvim" }

    -- AUTO-COMPLETE
    use { "weilbith/nvim-code-action-menu", cmd = "CodeActionMenu" }

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
    use { "tomasiser/vim-code-dark" }
    use { "ellisonleao/gruvbox.nvim" }
    use { "nvim-lualine/lualine.nvim" }
    use {
        "jesseleite/nvim-noirbuddy",
        requires = { "tjdevries/colorbuddy.nvim", branch = "dev" }
    }
end)
