local M = {}

local fireworks = {}
local debri = {}
local elapsed = 0.0
local last_id = 1

local rotate = function(x, y, angle)
  local px = x * math.cos(angle) - y * math.sin(angle)
  local py = x * math.sin(angle) + y * math.cos(angle)

  return { px, py }
end

M.setup = function(opts)
  opts = opts or {}
end

M.prepare = function(rows, cols)
  local colors = { "#E40303", "#FF8C00", "#FFED00", "#008026", "#004CFF", "#732982" }

  for i = 0, 5, 1 do
    local f = {
      row = rows - 1,
      col = math.random(0, cols),
      drow = math.random(-15, -10),
      dcol = math.random(-10, 10),
      color = colors[math.random(1, #colors)]
    }

    f.key = string.format("r%sc%s", f.row, f.col)
    fireworks[f.key] = f
  end
end

M.update = function(dt)
  elapsed = elapsed + dt

  for k, f in pairs(fireworks) do
    f.row = f.row + f.drow * dt
    f.col = f.col + f.dcol * dt
    fireworks[k] = nil
    local new_k = string.format("r%sc%s", math.ceil(f.row), math.ceil(f.col))
    fireworks[new_k] = f
  end
end

M.get_color = function(row, col, rows, cols)
  local key = string.format("r%dc%d", row, col)

  if fireworks[key] then
    return fireworks[key].color
  end

  return "#FFFFFF"
end

return M
