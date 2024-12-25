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
      canvas.draw_rect(0, 0, canvas.rows, canvas.cols, { bg = "#FFFFFF", fg = "#FF0000", content = "X" })
    end,
  }
end


return M


































--
