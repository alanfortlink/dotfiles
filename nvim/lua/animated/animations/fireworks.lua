local utils = require("animated.utils")

local M = {}

M.id = "fireworks"

M.create = function(opts)
  local elapsed = 0.0
  local fireworks = {}
  local particles = {}
  local gravity = 10.0

  local move = function(obj, dt)
    obj.row_speed = obj.row_speed + gravity * dt
    obj.col = obj.col + obj.col_speed * dt
    obj.row = obj.row + obj.row_speed * dt
  end

  local I = {
    init = function()
      M.opts = opts
      gravity = 0.05 * opts.rows

      elapsed = 0.0
      for i = 0, 20, 1 do
        local col = math.random(0, opts.cols)
        local row = opts.rows + i * 0.2 * opts.rows

        local row_speed = -math.random(0.4 * opts.rows, 0.8 * opts.rows)
        local col_speed = math.random(-15, 15)

        local row_limit = math.random(0.2 * opts.rows, 0.3 * opts.rows)

        local color = "#FFFFFF"

        local firework = {
          col = col,
          row = row,
          row_speed = row_speed,
          col_speed = col_speed,
          color = color,
          row_limit = row_limit,
        }

        table.insert(fireworks, firework)
      end
    end,

    update = function(dt)
      elapsed = elapsed + dt

      local filtered_fireworks = {}
      for _, f in ipairs(fireworks) do
        move(f, dt)
        if f.row > f.row_limit and f.row_speed < 0 then
          table.insert(filtered_fireworks, f)
        else
          local num_particles = 16.0
          for i = 0, num_particles - 1, 1 do
            local angle = 2 * math.pi * (i / (num_particles))
            local row_speed, col_speed = utils.rotate(8, 0, angle)
            row_speed = row_speed + 0.1 * f.row_speed
            -- col_speed = col_speed * (M.opts.cols / M.opts.rows)

            local particle = {
              row = f.row,
              col = f.col,
              row_speed = row_speed,
              col_speed = col_speed,
              color = f.color,
            }

            table.insert(particles, particle)
          end
        end
      end

      for _, p in ipairs(particles) do
        move(p, dt)
      end

      fireworks = filtered_fireworks

      return elapsed <= 10
    end,

    render = function(canvas)
      for _, f in ipairs(fireworks) do
        canvas.draw_rect(f.row, f.col, 1, 1, { bg = f.color })
      end

      for _, p in ipairs(particles) do
        canvas.draw_rect(p.row, p.col, 1, 1, { fg = p.color, content = "*" })
      end
    end

  }
  return I;
end

return M



















--
