local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local make_entry = require("telescope.make_entry")
local conf = require("telescope.config").values

local M = {}

local live_multigrep = function(opts)
  opts = opts or {}
  opts.cwd = opts.cwd or vim.uv.cwd()

  local finder = finders.new_async_job {
    command_generator = function(prompt)
      if not prompt or prompt == "" then
        return nil
      end

      local parts = vim.split(prompt, "  ")
      local args = { "rg" }

      if parts[1] then
        table.insert(args, "-e")
        table.insert(args, parts[1])
      end

      local i = 2
      while parts[i] do
        if parts[i] then
          table.insert(args, "-g")
          if string.find(parts[i], "*") then
            table.insert(args, parts[i])
          else
            table.insert(args, string.format("*.%s", parts[i]))
          end
        end
        i = i + 1
      end

      ---@diagnostic disable-next-line: deprecated
      return vim.tbl_flatten({
        args,
        {
          "--color=never",
          "--no-heading",
          "--with-filename",
          "--line-number",
          "--column",
          "--smart-case",
        },
      })
    end,
    entry_maker = make_entry.gen_from_vimgrep(opts),
    cwd = opts.cwd,
  }

  pickers.new(opts, {
    debounce = 100,
    prompt = "Multi Grep",
    finder = finder,
    previewer = conf.grep_previewer(opts),
    sorter = require("telescope.sorters").empty()
  }):find();
end

M.live_multigrep = live_multigrep;

return M
