local M = {}

M.get_win_size = function(window)
  return vim.api.nvim_win_get_height(window), vim.api.nvim_win_get_width(window)
end

M.get_scroll = function(window)
  local view = vim.fn.winsaveview()
  return view.topline, view.leftcol
end

return M
