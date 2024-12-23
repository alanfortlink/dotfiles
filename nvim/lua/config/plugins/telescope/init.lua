return {
  {
    'nvim-telescope/telescope.nvim',
    lazy = false,
    config = function()
      require("telescope").setup({
        pickers = {
          find_files = {
          },
        },
        defaults = require('telescope.themes').get_ivy {
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
      local live_multigrep = require("config.plugins.telescope.multigrep").live_multigrep

      -- Find files
      vim.keymap.set("n", "<leader>f", function() t.find_files({ hidden = false }) end, { noremap = true })

      -- Find with hidden files
      vim.keymap.set("n", "<leader>F", function() t.find_files({ hidden = true }) end, { noremap = true })

      -- Commands
      vim.keymap.set("n", "<localleader>c", t.commands, { noremap = true })
      vim.keymap.set("n", "<localleader>h", t.help_tags, { noremap = true })

      -- Almighty GREP
      vim.keymap.set("n", "<leader>g", live_multigrep, { noremap = true })
      vim.keymap.set("v", "<leader>g", t.grep_string, { noremap = true })

      -- Other telescope stuff
      vim.keymap.set("n", "<localleader><localleader>", t.resume, { noremap = true })
      vim.keymap.set("n", "<leader><localleader>", t.builtin, { noremap = true })

      vim.keymap.set("n", "<localleader>d", function()
        require('telescope.builtin').find_files {
          cwd = vim.fn.stdpath("config"),
          hidden = true,
        }
      end)


      vim.keymap.set("n", "gS", t.lsp_document_symbols, { noremap = true })
    end,
    dependencies = { 'nvim-lua/plenary.nvim', },
  },


  {
    'nvim-telescope/telescope-ui-select.nvim',
    config = function()
      require("telescope").setup {
        extensions = {
          ["ui-select"] = {
            require("telescope.themes").get_dropdown {}
          }
        }
      }
      -- To get ui-select loaded and working with telescope, you need to call
      -- load_extension, somewhere after setup function:
      require("telescope").load_extension("ui-select")
    end
  },
}
