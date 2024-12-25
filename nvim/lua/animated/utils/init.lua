local M = {}

local get_rows = function(window)
  return math.min(vim.api.nvim_buf_line_count(0), vim.api.nvim_win_get_height(window))
end

M.get_win_size = function(window)
  return get_rows(window), vim.api.nvim_win_get_width(window)
end

M.get_scroll = function(window)
  local view = vim.fn.winsaveview()
  return view.topline, view.leftcol
end

M.rotate = function(row, col, angle)
  local r_row = row * math.cos(angle) - col * math.sin(angle)
  local r_col = row * math.sin(angle) + col * math.cos(angle)

  return r_row, r_col
end

return M
