return {
  {
    "folke/trouble.nvim",
    opts = {}, -- for default options, refer to the configuration section for custom setup.
    cmd = "Trouble",
    keys = {
      {
        "<leader>xx",
        "<cmd>Trouble diagnostics toggle<cr>",
        desc = "Diagnostics (Trouble)",
      },
      {
        "<leader>xX",
        "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
        desc = "Buffer Diagnostics (Trouble)",
      },
      {
        "<leader>xe",
        "<cmd>Trouble diagnostics toggle filter.severity=vim.diagnostic.severity.ERROR<cr>",
        desc = "Diagnostics (Errors only)",
      },
      {
        "<localleader>q",
        "<cmd>Trouble qflist toggle<cr>",
        desc = "Quickfix List (Trouble)",
      },
      {
        "<leader>xl",
        "<cmd>Trouble lsp toggle<cr>",
        desc = "LSP Info (Trouble)",
      },
      {
        "<leader>xl",
        "<cmd>Trouble lsp_incoming_calls toggle<cr>",
        desc = "LSP incoming Info (Trouble)",
      },
      {
        "<leader>xr",
        "<cmd>Trouble lsp_outgoing_calls toggle<cr>",
        desc = "LSP outgoing Info (Trouble)",
      },
      {
        "<leader>xd",
        "<cmd>Trouble diagnostics toggle filter.severity=vim.diagnostic.severity.HINT<cr>",
        desc = "Diagnostics (Hints only)",
      },
    },
  },
}
