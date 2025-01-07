return {
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
        -- {
        --   name = "Attach",
        --   type = "codelldb",
        --   request = "attach",
        --   program = function() return require("dap.utils").pick_file({}) end,
        --   pid = require("dap.utils").pick_process,
        --   cwd = '${workspaceFolder}'
        -- },
        {
          name = "Launch",
          type = "codelldb",
          request = "launch",
          program = function() return require("dap.utils").pick_file({}) end,
          cwd = '${workspaceFolder}',
        },
      };

      dap.configurations.c = dap.configurations.cpp;
      dap.configurations.rust = dap.configurations.cpp;

      -- dap adapter for c++ setup
      vim.keymap.set("n", "<localleader>b", dap.toggle_breakpoint)
      vim.keymap.set("n", "<localleader>dc", dap.continue)

      vim.keymap.set("n", "<localleader>dt", ui.toggle)

      vim.keymap.set("n", "??", function()
        require("dapui").eval(nil, { enter = true })
      end)

      vim.keymap.set("n", "<F4>", dap.run_to_cursor)
      vim.keymap.set("n", "<F5>", dap.continue)
      vim.keymap.set("n", "<F6>", dap.step_over)
      vim.keymap.set("n", "<F7>", dap.step_into)
      vim.keymap.set("n", "<F8>", dap.step_out)
      vim.keymap.set("n", "<F9>", dap.step_back)
      vim.keymap.set("n", "<F10>", dap.restart)
    end
  },
}
