return {
  dir = '~/repos/animatedbg.nvim',
  lazy = false,
  config = function()
    require("animatedbg-nvim").setup({ fps = 120 })

    vim.keymap.set("n", "<localleader>f", function()
      local animated = require("animatedbg-nvim")
      animated.play({ animation = "fireworks" })
    end, {})

    vim.keymap.set("n", "<localleader>ff", function()
      local animated = require("animatedbg-nvim")
      animated.play({ animation = "fireworks", duration = 500 })
    end, {})

    vim.keymap.set("n", "<localleader>fff", function()
      local animated = require("animatedbg-nvim")
      animated.play({ animation = "fireworks", duration = 500, time_between_shots = 0.1 })
    end, {})

    vim.keymap.set("n", "<localleader>e", function()
      local animated = require("animatedbg-nvim")
      animated.play({ animation = "demo" })
    end, {})

    vim.keymap.set("n", "<localleader>w", function()
      local animated = require("animatedbg-nvim")
      animated.play({ animation = "anim_skeleton" })
    end, {})

    vim.keymap.set("n", "<localleader>m", function()
      local animated = require("animatedbg-nvim")
      animated.play({ animation = "matrix" })
    end, {})

    vim.keymap.set("n", "<localleader>mm", function()
      local animated = require("animatedbg-nvim")
      animated.play({ animation = "matrix", duration = 500 })
    end, {})

    vim.keymap.set("n", "<localleader>mmm", function()
      local animated = require("animatedbg-nvim")
      animated.play({
        animation = "matrix",
        symbols = { "A", "B", "🔥" },
      })
    end, {})

    vim.keymap.set("n", "<localleader>M", function()
      require("animatedbg-nvim").stop_all()
    end, {})
  end
}

--return {
--  'alanfortlink/animatedbg.nvim',
--  config = function()
--    require("animatedbg-nvim").setup({
--      fps = 60   -- default
--    })
--  end
--}
