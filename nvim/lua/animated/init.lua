---@diagnostic disable: unused-local
local executor = require("animated.executor")

local M = {}

--- Local module to keep internal state
local internal = {}

--- Stores information about the animations currently in progress
--- key: the coroutine id for the given animation
--- value: table containing the animation opts
internal.in_progress = {}

--- Stores the list of the animations that can be played
--- key: a string with the animation name
--- value: a function that when called, returns an animation
internal.animations = {}

internal.on_animation_over = function(animation_id)
  local animation = internal.in_progress[animation_id]
  internal.in_progress[animation_id] = nil

  if animation.clean then
    animation.clean()
  end

  executor.clean(animation_id)
end

--- Configured the default options for animations
---@param opts table
M.setup = function(opts)
  opts = opts or {
  }

  opts.fps = opts.fps or 60
  internal.default_opts = opts

  local test_animation = require("animated.animations.test")
  internal.animations[test_animation.animation_id] = test_animation
end

local ERROR_OPTS_NIL = "`opts` cannot be nil."
local ERROR_NO_ANIMATION = "'%s' animation not found"

M.play = function(opts)
  if not opts then
    error(ERROR_OPTS_NIL);
    return
  end

  if not opts.animation or not internal.animations[opts.animation] then
    error(string.format(ERROR_NO_ANIMATION, opts.animation))
    return
  end

  local animation = internal.animations[opts.animation]
  local executor_opts = {
    animation = animation,
    fps = internal.default_opts.fps,
    on_animation_over = internal.on_animation_over,
    buffer = vim.api.nvim_get_current_buf(),
    window = vim.api.nvim_get_current_win(),
  }

  local animation_id = executor.create_animation(executor_opts)
  internal.in_progress[animation_id] = animation
end

return M
