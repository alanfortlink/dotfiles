local M = {}

local active_extmarks = {}
local active_hls = {}
local looping = false
local elapsed = 0
local duration = 10

local fps = 60
local delegate = nil

local get_buf = function()
  return 0
end

local get_win = function()
  return 0
end

local get_rows = function()
  local num_rows_in_text = vim.api.nvim_buf_line_count(get_buf());
  local num_rows_in_win = vim.api.nvim_win_get_height(get_win())

  return math.max(num_rows_in_text, num_rows_in_win)
end

local get_cols = function()
  return vim.api.nvim_win_get_width(get_win())
end

local get_line = function(row)
  return vim.api.nvim_buf_get_lines(get_buf(), row, row + 1, true)[1]
end

local get_ns_id = function()
  local ns_id = vim.api.nvim_create_namespace("AnimatedBG")
  return ns_id;
end

local get_hl = function(color)
  if active_hls[color] then
    return active_hls[color]
  end

  local hl_name = string.format("AnimatedBG%s", string.sub(color, 2))
  vim.api.nvim_set_hl(0, hl_name, { bg = color })

  active_hls[color] = hl_name
  return hl_name
end

M.setup = function(opts)
  if looping then
    return
  end
  opts = opts or {}
end

local clear = function()
  vim.api.nvim_buf_clear_namespace(0, get_ns_id(), 0, -1)
  for _, id in ipairs(active_extmarks) do
    vim.api.nvim_buf_del_extmark(get_buf(), get_ns_id(), id)
  end

  active_extmarks = {}
end

local update = function(dt)
  if not delegate then
    return
  end
  elapsed = elapsed + dt
  delegate.update(dt)
end

local render = function()
  if not delegate then
    return
  end

  local num_rows_in_text = vim.api.nvim_buf_line_count(get_buf());
  local num_rows_in_win = vim.api.nvim_win_get_height(get_win())

  local rows = get_rows()
  local cols = get_cols()

  for row = 0, rows - 1, 1 do
    local used_space = #get_line(row)

    for col = 0, used_space, 1 do
      local color = delegate.get_color(row, col, rows, cols)
      if not color then
        goto continue
      end
      vim.api.nvim_buf_add_highlight(0, get_ns_id(), get_hl(color), row, col, col + 1)

      ::continue::
    end

    local extmarks = {}
    for col = used_space, cols, 1 do
      local color = delegate.get_color(row, col, rows, cols)
      if color then
        table.insert(extmarks, { " ", get_hl(color) })
      else
        table.insert(extmarks, { " ", "@none" })
      end
    end

    local id = vim.api.nvim_buf_set_extmark(0, get_ns_id(), row, used_space, {
      virt_text = extmarks,
      virt_text_pos = "overlay",
      strict = false,
    })

    table.insert(active_extmarks, id);
  end
end

local _internal = {}
_internal._loop = function()
  looping = true
  clear()

  if elapsed >= duration then
    elapsed = 0
    delegate = nil
  end

  if delegate then
    update(1.0 / fps)
    render()
    vim.defer_fn(_internal._loop, (1000 / fps))
  end
end

M.start = function(opts)
  opts = opts or {}
  elapsed = 0

  if not opts.delegate then
    opts.delegate = require("animated.fireworks")
    opts.delegate.setup({})
  end

  opts.delegate.prepare(get_rows(), get_cols())

  delegate = opts.delegate
  fps = opts.fps or 60
  duration = opts.duration or 10

  if looping then
    return
  end
  _internal._loop()
end

M.setup({})
M.start({
})

return M
