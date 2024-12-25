local M = {}

local internal = {}
internal.last_id = 0
internal.animations = {}

local canvas = require("animated.canvas")
local render = require("animated.render")

local is_running = false
local global_dt = 0

internal.run = function()
  local count = 0
  canvas.clear()

  for id, animation in pairs(internal.animations) do
    animation.loop(global_dt)
    count = count + 1
  end

  if count > 0 then
    is_running = true
    vim.defer_fn(internal.run, global_dt * 1000)
    render.render(canvas)
    return
  end

  is_running = false
end

-- closure for the game loop
internal.get_new_game_loop = function(opts)
  return {
    start = function()
      canvas.setup(opts)
      opts.animation.init(opts)
    end,
    loop = function(dt)
      if opts.animation.update(dt) then
        opts.animation.render(canvas)
        return
      else
        local id = opts.id
        internal.animations[id] = nil
        render.clean(opts)
      end
    end,
  }
end

M.start_new_animation = function(opts)
  opts.id = tostring({}):sub(8)
  global_dt = 1.0 / opts.fps
  local game_loop = internal.get_new_game_loop(opts)
  internal.animations[opts.id] = game_loop
  game_loop.start()
  if not is_running then
    internal.run()
  end
end

return M
