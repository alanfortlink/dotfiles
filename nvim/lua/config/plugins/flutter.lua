return {
  "akinsho/flutter-tools.nvim",
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    require("flutter-tools").setup {
      decorations = {
        statusline = {
          -- set to true to be able use the 'flutter_tools_decorations.app_version' in your statusline
          -- this will show the current version of the flutter app from the pubspec.yaml file
          app_version = true,
          -- set to true to be able use the 'flutter_tools_decorations.device' in your statusline
          -- this will show the currently running device if an application was started with a specific
          -- device
          device = true,
        }
      },
      closing_tags = {
        highlight = "Comment", -- highlight for the closing tag
        prefix = "// ",        -- character to use for close tag e.g. > Widget
        enabled = true         -- set to false to disable
      },
      dev_log = {
        enabled = true,
        open_cmd = "vnew", -- command to use to open the log buffer
      },
      dev_tools = {
        autostart = true,          -- autostart devtools server if not detected
        auto_open_browser = false, -- Automatically opens devtools in the browser
      },
      outline = {
        open_cmd = "30vnew", -- command to use to open the outline buffer
        auto_open = false    -- if true this will open the outline automatically when it is first populated
      },
    }
  end,
}
