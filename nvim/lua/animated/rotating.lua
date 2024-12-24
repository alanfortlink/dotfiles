local M = {}

local pixels = {}
local locations = {}
local rotation_duration = 5.0;

M.setup = function(opts)
  opts = opts or {}
end

M.prepare = function(rows, cols)
  local colors = { "#E40303", "#FF8C00", "#FFED00", "#008026", "#004CFF", "#732982" }
  for row = 0, rows, 1 do
    for col = 0, cols, 1 do
      local pixel = {
        color = colors[((col - 1) % (#colors)) + 1],
        row = row,
        col = col
      }
      table.insert(pixels, pixel);
      locations[string.format("r%dc%d", row, col)] = pixel;
    end
  end
end

local elapsed = 0.0

local rotate = function(x, y, angle)
  local px = x * math.cos(angle) - y * math.sin(angle)
  local py = x * math.sin(angle) + y * math.cos(angle)

  return { px, py }
end

M.update = function(dt)
  elapsed = elapsed + dt

  local new_locations = {}
  local angle = math.pi * 2 * ((elapsed % rotation_duration) / rotation_duration)
    for k, v in pairs(locations) do
      local new_pos = rotate(v.row, v.col, angle)
      local key = string.format("r%dc%d", new_pos[1], new_pos[2])
      new_locations[key] = v
    end
    locations = new_locations
end

M.get_color = function(row, col, rows, cols)
  local key = string.format("r%dc%d", math.ceil(row - rows / 2), math.ceil(col - cols / 2))
  if locations[key] then
    return locations[key].color
  end

  return nil
end

return M
