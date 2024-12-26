local M = {}

local internal = {}
internal.active_hls = {}

internal.last_color_id = 0
internal.color_to_id = {}

internal.last_content_id = 0
internal.content_to_id = {}

M.raw_canvas = {}

M.setup = function(opts)
  M.raw_canvas = {}

  for i = 0, opts.rows - 1, 1 do
    M.raw_canvas[i] = {}
    for j = 0, opts.cols - 1, 1 do
      M.raw_canvas[i][j] = { content = nil, bg = nil, fg = nil }
    end
  end

  M.rows = opts.rows
  M.cols = opts.cols
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

  internal.active_hls[key] = { hl = hl_name, content = cell.content }
  return { hl = hl_name, content = cell.content }
end

M.clear = function()
  for i = 0, M.rows - 1, 1 do
    M.raw_canvas[i] = {}
    for j = 0, M.cols - 1, 1 do
      M.raw_canvas[i][j] = { content = nil, bg = nil, fg = nil }
    end
  end
end

M.draw_rect = function(rect, decoration, opts)
  opts = opts or {}
  local painting_style = opts.painting_style or "fill"

  local end_row = rect.row + rect.rows
  for i = rect.row, end_row - 1, 1 do
    i = math.floor(i)

    if not M.raw_canvas[i] then
      goto next_row
    end

    local end_col = rect.col + rect.cols
    for j = rect.col, end_col - 1, 1 do
      j = math.floor(j)

      if not M.raw_canvas[i][j] then
        goto next_column
      end

      if painting_style == "empty" then
        if i > rect.row and i < end_row - 1 and j > rect.col and j < end_col - 1 then
          goto next_column
        end
      end

      M.raw_canvas[i][j] = decoration

      ::next_column::
    end

    ::next_row::
  end
end

M.draw_circle = function(circle, decoration, opts)
  opts = opts or {}
  local painting_style = opts.painting_style or "fill"
  local adjust_aspect_ratio = opts.adjust_aspect_ratio or false

  local row_adjustment = 0
  local col_adjustment = 0

  local radius = circle.radius

  if adjust_aspect_ratio then
    if M.cols > M.rows then
      local fac = M.rows / M.cols
      col_adjustment = 0.5 * fac * circle.radius
    else
      local fac = M.cols / M.rows
      row_adjustment = 0.5 * fac * circle.radius
    end
  end

  local rect = {
    row = circle.center.row - radius - row_adjustment,
    col = circle.center.col - radius - col_adjustment,
    rows = 2 * radius + 2 * row_adjustment,
    cols = 2 * radius + 2 * col_adjustment,
  }

  local end_row = rect.row + rect.rows
  for i = rect.row, end_row, 1 do
    i = math.floor(i)

    if not M.raw_canvas[i] then
      goto next_row
    end

    local end_col = rect.col + rect.cols
    for j = rect.col, end_col, 1 do
      j = math.floor(j)

      if not M.raw_canvas[i][j] then
        goto next_column
      end

      local dist = math.sqrt(math.pow(circle.center.row - i, 2) + math.pow(circle.center.col - j, 2))

      if painting_style == "empty" then
        if math.abs(dist - radius) > 1 then
          goto next_column
        end
      end

      if dist > radius then
        goto next_column
      end

      M.raw_canvas[i][j] = decoration

      ::next_column::
    end

    ::next_row::
  end
end

local function get_point_status(polygon, point, threshold)
  local vertices = polygon.vertices
  local x, y = point.col, point.row
  local inside = false
  local n = #vertices
  local j = n

  for i = 1, n do
    local xi, yi = vertices[i].col, vertices[i].row
    local xj, yj = vertices[j].col, vertices[j].row

    -- Check for border using distance from line segment
    local dx, dy = xj - xi, yj - yi
    local t = ((x - xi) * dx + (y - yi) * dy) / (dx * dx + dy * dy)
    t = math.max(0, math.min(1, t))
    local closestX, closestY = xi + t * dx, yi + t * dy
    local dist = math.sqrt((x - closestX) ^ 2 + (y - closestY) ^ 2)

    if dist <= threshold then
      return "border"
    end

    -- Ray-casting for inside check
    if ((yi > y) ~= (yj > y)) and
        (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
      inside = not inside
    end

    j = i
  end

  return inside and "inside" or "outside"
end


M.draw_polygon = function(polygon, decoration, opts)
  opts = opts or {}
  local painting_style = opts.painting_style or "fill"

  local top_row = M.rows
  local bottom_row = 0

  local left_col = M.cols
  local right_col = 0

  for i, p in ipairs(polygon.vertices) do
    top_row = math.min(top_row, p.row)
    left_col = math.min(left_col, p.col)

    bottom_row = math.max(bottom_row, p.row)
    right_col = math.max(right_col, p.col)
  end

  local rect = {
    row = top_row,
    col = left_col,
    rows = bottom_row - top_row + 1,
    cols = right_col - left_col + 1,
  }

  local end_row = rect.row + rect.rows
  for i = rect.row, end_row - 1, 1 do
    i = math.floor(i)

    if not M.raw_canvas[i] then
      goto next_row
    end

    local end_col = rect.col + rect.cols
    for j = rect.col, end_col - 1, 1 do
      j = math.floor(j)

      if not M.raw_canvas[i][j] then
        goto next_column
      end

      local status = get_point_status(polygon, { row = i, col = j }, 2)

      if painting_style == "empty" and status ~= "border" then
        goto next_column
      end

      if status == "outside" then
        goto next_column
      end

      M.raw_canvas[i][j] = decoration

      ::next_column::
    end

    ::next_row::
  end
end

return M
