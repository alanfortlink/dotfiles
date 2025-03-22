return {
  {
    "airblade/vim-gitgutter",
    lazy = false,
    keys = {
      { "]h", "<cmd>GitGutterNextHunk<CR>zz",    desc = "Next GitGutter Hunk" },
      { "[h", "<cmd>GitGutterPrevHunk<CR>zz",    desc = "Previous GitGutter Hunk" },
      { "HH", "<cmd>GitGutterPreviewHunk<CR>zz", desc = "Previous GitGutter Hunk" },
    },
  },
  {
    "lewis6991/gitsigns.nvim",
    lazy = false,
    opts = {},
  }
}
