vim.cmd [[packadd packer.nvim]]

require('packer').startup(function()
    -- PACKER.NVIM
    use 'wbthomason/packer.nvim'

    -- TOOLS
    use 'tpope/vim-fugitive'
    use 'mbbill/undotree'
    use 'tpope/vim-eunuch' -- Rename, Move, CFind, Move
    use 'vim-scripts/DoxygenToolkit.vim'
    use 'jremmen/vim-ripgrep'
    use 'farmergreg/vim-lastplace'
    use 'nvim-treesitter/nvim-treesitter'
    -- use {
    --     'thmsmlr/nvim-treesitter',
    -- }

    -- FLUTTER
    use 'thosakwe/vim-flutter'

    -- NAVIGATION
    use 'scrooloose/nerdtree'
    use 'justinmk/vim-sneak'
    use {
        'nvim-telescope/telescope.nvim',
        requires = { { 'nvim-lua/plenary.nvim' } }
    }

    -- AUTO-COMPLETE
    use 'neovim/nvim-lspconfig'
    use 'hrsh7th/nvim-cmp'
    use 'hrsh7th/cmp-nvim-lsp'
    use 'L3MON4D3/LuaSnip'
    use 'saadparwaiz1/cmp_luasnip'
    require('packer').use({
        'weilbith/nvim-code-action-menu',
        cmd = 'CodeActionMenu',
    })

    -- EDIT
    use 'tommcdo/vim-exchange'
    use 'tpope/vim-surround'

    -- STYLE
    use 'airblade/vim-gitgutter'
    use 'tomasiser/vim-code-dark'
    use { "ellisonleao/gruvbox.nvim" }
    use {
        'nvim-lualine/lualine.nvim',
    }
end
)

