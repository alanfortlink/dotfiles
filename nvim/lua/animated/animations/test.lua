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
      local rect = {
        row = 0,
        col = 0,
        rows = canvas.rows,
        cols = canvas.cols,
      }

      local decoration = { bg = "#FFFFFF", fg = "#FF0000", content = "X" }
      canvas.draw_rect(rect, decoration, { painting_style = "empty" })
    end,
  }
end


return M


































--
