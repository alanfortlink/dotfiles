local M = {}

local elapsed = 0.0

M.id = "test"

M.create = function(opts)
  return {
    init = function()
      elapsed = 0.0
    end,

    update = function(dt)
      elapsed = elapsed + dt
      return elapsed <= 2 -- Animation is over after 3 seconds
    end,

    render = function(canvas)
      -- local rect = {
      --   row = 0,
      --   col = 0,
      --   rows = canvas.rows,
      --   cols = canvas.cols,
      -- }

      -- canvas.draw_rect(rect, decoration, { painting_style = "line" })
      local polygon = {
        vertices = {
          { row = canvas.rows * 0.2, col = canvas.cols * 0.5 },
          { row = canvas.rows * 0.6, col = canvas.cols * 0.2 },
          { row = canvas.rows * 0.8, col = canvas.cols * 0.5 },
          { row = canvas.rows * 0.6, col = canvas.cols * 0.8 },
        }
      }
      local decoration = { bg = "#FFFFFF", fg = "#FF0000", content = "X" }
      canvas.draw_polygon(polygon, decoration, { painting_style = "line" })

      local polygon2 = {
        vertices = {
          { row = canvas.rows * 0.1, col = canvas.cols * 0.7 },
          { row = canvas.rows * 0.3, col = canvas.cols * 0.5 },
          { row = canvas.rows * 0.1, col = canvas.cols * 0.3 },
        }
      }
      canvas.draw_polygon(polygon2, decoration, { painting_style = "fill" })

      canvas.draw_rect({ row = 0, col = 0, rows = 10, cols = 10 }, decoration)
      canvas.draw_rect({ row = 20, col = 0, rows = 10, cols = 10 }, decoration, { painting_style = "line" })

      canvas.draw_circle({ center = { row = 30, col = canvas.cols - 30 }, radius = 5 }, decoration, { painting_style = "fill" })
      canvas.draw_circle({ center = { row = 15, col = 15 }, radius = 5 }, decoration, { painting_style = "line" })
    end,
  }
end


return M


































--
