local M = {}

local get_rows = function(window)
  return math.min(vim.api.nvim_buf_line_count(0), vim.api.nvim_win_get_height(window))
end

local get_cols = function(window)
  local total_width = vim.api.nvim_win_get_width(window)
  local number_width = vim.wo[window].number and vim.wo[window].numberwidth or 0
  local sign_column_width = vim.wo[window].signcolumn == "yes" and 2
      or (vim.wo[window].signcolumn == "auto" and 2 or 0)
  local fold_column_width = vim.wo[window].foldcolumn and tonumber(vim.wo[window].foldcolumn) or 0

  return total_width - number_width - sign_column_width - fold_column_width
end

M.get_win_size = function(window)
  return get_rows(window), get_cols(window)
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
