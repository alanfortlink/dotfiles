-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out,                            "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Setup lazy.nvim
require("lazy").setup({
  spec = {
    { import = "config.plugins" },
    { "tommcdo/vim-exchange",     lazy = false },
    -- { "tpope/vim-surround",       lazy = false },
    { "kylechui/nvim-surround", lazy = false, opts={} },
    { "farmergreg/vim-lastplace", lazy = false },
    { "karb94/neoscroll.nvim",    opts = { easing_function = "quadratic" } },
    { 'numToStr/Comment.nvim' },
    { "github/copilot.vim" },
    {
      'stevearc/oil.nvim',
      opts = {},
      dependencies = { "nvim-tree/nvim-web-devicons" }
    },
    { 'alanfortlink/blackjack.nvim' },
    { "danymat/neogen",             config = true, }

  }
})
