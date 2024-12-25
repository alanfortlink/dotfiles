local utils = require("animated.utils")

local M = {}

local internal = {}

internal.active_extmarks = {}
internal.ns_id = vim.api.nvim_create_namespace("animated")

internal.get_line = function(buf, row)
  return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

internal.clean = function(buffer)
  vim.api.nvim_buf_clear_namespace(0, internal.ns_id, 0, -1)
  for _, id in ipairs(internal.active_extmarks) do
    vim.api.nvim_buf_del_extmark(buffer, internal.ns_id, id)
  end

  internal.active_extmarks = {}
end

M.clean = function(opts)
  internal.clean(opts.buffer)
end

M.render = function(opts, canvas)
  canvas.prerender()
  internal.clean(opts.buffer)

  local rows, cols = utils.get_win_size(opts.window)
  local row_scroll, col_scroll = utils.get_scroll()

  for row = 0, rows - 1, 1 do
    local real_row = row + row_scroll - 1
    local used_space = #internal.get_line(opts.buffer, real_row)

    for col = 0, used_space, 1 do
      local bundle = canvas.get_hl(row, col)
      if not bundle then
        goto continue
      end
      local hl = bundle.hl
      -- local content = bundle.content
      vim.api.nvim_buf_add_highlight(0, internal.ns_id, hl, real_row, col, col + 1)

      ::continue::
    end

    local extmarks = {}
    for col = used_space, cols + col_scroll, 1 do
      local bundle = canvas.get_hl(row, col)
      if bundle then
        table.insert(extmarks, { bundle.content or " ", bundle.hl })
      else
        table.insert(extmarks, { " ", "@none" })
      end
    end

    local id = vim.api.nvim_buf_set_extmark(opts.buffer, internal.ns_id, real_row, used_space, {
      virt_text = extmarks,
      virt_text_pos = "overlay",
      strict = false,
    })

    table.insert(internal.active_extmarks, id);
  end
end

return M