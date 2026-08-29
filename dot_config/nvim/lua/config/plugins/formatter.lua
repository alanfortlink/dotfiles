return {
  { -- Autoformat
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    lazy = false,
    cmd = { "ConformInfo" },
    keys = {
      {
        "<leader><leader>",
        function()
          require("conform").format({ async = false, lsp_format = "fallback" })
          print("Buffer formatted")
        end,
        mode = { "n", "x" },
        desc = "[F]ormat buffer",
      },
    },
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        -- Disable "format_on_save lsp_fallback" for languages that don't
        -- have a well standardized coding style.
        local disable_filetypes = {}
        if disable_filetypes[vim.bo[bufnr].filetype] then
          return nil
        end
        return {
          timeout_ms = 500,
          lsp_format = "fallback",
        }
      end,
      formatters_by_ft = {
        lua = { "stylua" },
        cpp = { "clang-format" },
        c = { "clang-format" },
        python = { "black", "isort", stop_after_first = true },
        --
        -- You can use 'stop_after_first' to run the first available formatter from the list
        -- javascript = { "prettierd", "prettier", stop_after_first = true },
      },
    },
  },
}
