local M = {}

local internal = {}
internal.last_id = 0
internal.local_id_to_coroutine_id = {}
internal.coroutines = {}

internal.run = function(id, opts)
  local dt = 1000.0 / opts.fps
  if internal.coroutines[id] then
    local coro = internal.coroutines[id]
    coroutine.resume(coro)
    vim.defer_fn(function() internal.run(id, opts) end, dt)
  end
end

-- closure for the game loop
internal.get_new_game_loop = function(opts)
  -- game loop
  return function()
    local canvas = require("animated.canvas")
    local render = require("animated.render")
    local dt = 1.0 / opts.fps
    canvas.setup(opts)
    opts.animation.init()
    while opts.animation.update(dt) do
      opts.animation.render(canvas)
      render.render(opts, canvas)
      coroutine.yield()
    end
    local id = internal.local_id_to_coroutine_id[opts.animation_id]
    internal.local_id_to_coroutine_id[opts.animation] = nil
    opts.on_animation_over(id)
    render.clean(opts)
  end
end

M.create_animation = function(opts)
  internal.last_id = internal.last_id + 1
  opts.animation_id = internal.last_id
  local game_loop = internal.get_new_game_loop(opts)
  local coro = coroutine.create(game_loop)
  local id = tostring(coro):sub(8) -- extracts the "address" part
  internal.local_id_to_coroutine_id[opts.animation_id] = id

  coroutine.resume(coro)
  internal.coroutines[id] = coro

  internal.run(id, opts)
  return id
end

M.clean = function(id)
  internal.coroutines[id] = nil
end

return M
