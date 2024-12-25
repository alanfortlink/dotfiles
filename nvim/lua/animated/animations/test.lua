local M = {}

local elapsed = 0.0

M.id = "test"

M.init = function(opts)
  elapsed = 0.0
end

M.update = function(dt)
  elapsed = elapsed + dt
  return elapsed <= 2 -- Animation is over after 3 seconds
end

M.render = function(canvas)
  canvas.draw_rect(0, 0, canvas.rows, canvas.cols, { bg = "#FFFFFF", fg="#FF0000", content="X" })
end

return M


































--
