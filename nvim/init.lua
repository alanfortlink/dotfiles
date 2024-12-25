require("sets")
require("mappings")
require("terminal")
require("utils")

require("config.lazy")

vim.keymap.set("n", "<localleader>r", function()
  for name, _ in pairs(package.loaded) do
    if vim.startswith(name, "animated") then
      package.loaded[name] = nil
    end
  end

end, {})

vim.keymap.set("n", "<localleader>f", function()
  local animated = require("animated")
  animated.setup({})
  animated.play({ animation = "fireworks" })
end, {})

vim.keymap.set("n", "<localleader>e", function()
  local animated = require("animated")
  animated.setup({})
  animated.play({ animation = "test" })
end, {})
