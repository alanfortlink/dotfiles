local utils = require("animated.utils")

local M = {}

local internal = {}
internal.active_hls = {}

internal.last_color_id = 0
internal.color_to_id = {}

internal.last_content_id = 0
internal.content_to_id = {}

M.raw_canvas = {}

M.setup = function(opts)
  local rows, cols = utils.get_win_size(opts.window)
  M.raw_canvas = {}

  for i = 0, rows, 1 do
    M.raw_canvas[i] = {}
    for j = 0, cols, 1 do
      M.raw_canvas[i][j] = { content = nil, bg = nil, fg = nil }
    end
  end

  internal.opts = opts
  M.rows = rows
  M.cols = cols
end

M.prerender = function()
end

M.get_hl = function(row, col)
  local cell = M.raw_canvas[row][col]
  if not cell then
    return nil
  end

  if not cell.content and not cell.bg and not cell.fg then
    return nil
  end

  local content_id = nil
  local bg_id = nil
  local fg_id = nil

  if cell.content then
    if internal.content_to_id[cell.content] then
      content_id = internal.content_to_id[cell.content]
    else
      internal.last_content_id = internal.last_content_id + 1
      internal.content_to_id[cell.content] = internal.last_content_id
      content_id = internal.last_content_id
    end
  end

  if cell.bg then
    if internal.color_to_id[cell.bg] then
      bg_id = internal.color_to_id[cell.bg]
    else
      internal.last_color_id = internal.last_color_id + 1
      internal.color_to_id[cell.bg] = internal.last_color_id
      bg_id = internal.last_color_id
    end
  end

  if cell.fg then
    if internal.color_to_id[cell.fg] then
      fg_id = internal.color_to_id[cell.fg]
    else
      internal.last_color_id = internal.last_color_id + 1
      internal.color_to_id[cell.fg] = internal.last_color_id
      fg_id = internal.last_color_id
    end
  end

  local key = string.format("c%sf%sb%s", content_id, bg_id, fg_id)

  if internal.active_hls[key] then
    return internal.active_hls[key]
  end

  local hl_name = string.format("AnimBG%s", key)
  vim.api.nvim_set_hl(0, hl_name, { bg = cell.bg, fg = cell.fg })

  internal.active_hls[key] = {hl = hl_name, content = cell.content}
  return {hl = hl_name, content = cell.content}
end

M.clear = function()
  local rows, cols = utils.get_win_size(internal.opts.window)
  for i = 0, rows, 1 do
    M.raw_canvas[i] = {}
    for j = 0, cols, 1 do
      M.raw_canvas[i][j] = { content = nil, bg = nil, fg = nil }
    end
  end
end

M.draw_rect = function(row, col, rows, cols, opts)
  for i = row, row + rows-1, 1 do
    i = math.floor(i)
    if not M.raw_canvas[i] then
      goto row_continue
    end

    for j = col, col + cols-1, 1 do
      j = math.floor(j)
      if not M.raw_canvas[i][j] then
        goto col_continue
      end

      M.raw_canvas[i][j] = opts

      ::col_continue::
    end

    ::row_continue::
  end
end

return M
