---@diagnostic disable: unused-local
local executor = require("animated.executor")
local utils = require("animated.utils")

local M = {}

--- Local module to keep internal state
local internal = {}

--- Stores the list of the animations that can be played
--- key: a string with the animation name
--- value: a function that when called, returns an animation
internal.animations = {}

--- Configured the default options for animations
---@param opts table
M.setup = function(opts)
  opts = opts or {
  }

  opts.fps = opts.fps or 60
  internal.default_opts = opts

  local test_animation = require("animated.animations.test")
  local fireworks_animation = require("animated.animations.fireworks")

  internal.animations[test_animation.id] = test_animation
  internal.animations[fireworks_animation.id] = fireworks_animation
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
    buffer = vim.api.nvim_get_current_buf(),
    window = vim.api.nvim_get_current_win(),
  }

  local rows, cols = utils.get_win_size(executor_opts.window)
  executor_opts.rows = rows
  executor_opts.cols = cols

  executor.start_new_animation(executor_opts)
end

return M
