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

      -- canvas.draw_rect(rect, decoration, { painting_style = "empty" })
      local polygon = {
        vertices = {
          { row = canvas.rows * 0.2, col = canvas.cols * 0.5 },
          { row = canvas.rows * 0.6, col = canvas.cols * 0.2 },
          { row = canvas.rows * 0.8, col = canvas.cols * 0.5 },
          { row = canvas.rows * 0.6, col = canvas.cols * 0.8 },
        }
      }
      local decoration = { bg = "#FFFFFF", fg = "#FF0000", content = "X" }
      canvas.draw_polygon(polygon, decoration)
    end,
  }
end


return M


































--
