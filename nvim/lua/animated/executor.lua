local M = {}

local internal = {}
internal.last_id = 0
internal.animations = {}

local canvas = require("animated.canvas")
local render = require("animated.render")

canvas.setup()

is_execution_running = false
local global_dt = 0

internal.run = function()
  local count = 0
  canvas.clear()

  for id, animation in pairs(internal.animations) do
    animation.loop(global_dt)
    count = count + 1
  end

  render.render(canvas)

  if count > 0 then
    vim.defer_fn(internal.run, global_dt * 1000)
    return
  end

  is_execution_running = false
end

internal.get_new_game_loop = function(opts)
  return {
    start = function()
      opts.animation.init()
    end,
    loop = function(dt)
      if opts.animation.update(dt) then
        opts.animation.render(canvas)
        return
      else
        internal.animations[opts.id] = nil
      end
    end,
  }
end

M.start_new_animation = function(opts)
  opts.id = tostring({}):sub(8)
  opts.animation = opts.animation.create(opts)

  global_dt = 1.0 / opts.fps
  local game_loop = internal.get_new_game_loop(opts)
  internal.animations[opts.id] = game_loop
  game_loop.start()

  if not is_execution_running then
    is_execution_running = true
    internal.run()
  end
end

return M
