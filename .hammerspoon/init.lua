hs.hotkey.bind({ "alt", "ctrl" }, "r", function()
	hs.reload()
end)

local AC = { "alt", "ctrl" }
local ACS = { "alt", "ctrl", "shift" }

local setFrameSize = function(xf, yf, wf, hf, key)
	local win = hs.window.focusedWindow()
	local sf = win:screen():frame()

  local newFrame = {
		x = sf.x + sf.w * xf, -- <-- add the screen offset
		y = sf.y + sf.h * yf,
		w = sf.w * wf,
		h = sf.h * hf,
	}

  if newFrame.w == win:frame().w then
    newFrame.w = sf.w * (1 - wf)
  end

	win:setFrame(newFrame)
end

local setFrameResize = function(wf, hf)
	local win = hs.window.focusedWindow()
	local windowFrame = win:frame()
	local screenFrame = hs.screen.mainScreen():frame()

	windowFrame.w = windowFrame.w + screenFrame.w * wf
	windowFrame.h = windowFrame.h + screenFrame.h * hf

	-- Ensure the window does not exceed the screen bounds
	if windowFrame.w < 0 then
		windowFrame.w = 0
	end
	if windowFrame.h < 0 then
		windowFrame.h = 0
	end
	if windowFrame.w > screenFrame.w then
		windowFrame.w = screenFrame.w
	end
	if windowFrame.h > screenFrame.h then
		windowFrame.h = screenFrame.h
	end

	win:setFrame(windowFrame)
end

local frameSizeBind = function(meta, key, xf, yf, wf, hf)
	hs.hotkey.bind(meta, key, function()
		setFrameSize(xf, yf, wf, hf, key)
	end)
end

local frameResizeBind = function(meta, key, wf, hf)
	hs.hotkey.bind(meta, key, function()
		setFrameResize(wf, hf)
	end)
end

frameSizeBind(AC, "h", 0, 0, 0.5, 1)
frameSizeBind(ACS, "h", 0, 0, 0.75, 1)
frameSizeBind(AC, "l", 0.5, 0, 0.5, 1)
frameSizeBind(ACS, "l", 0.75, 0, 0.25, 1)

frameSizeBind(AC, "j", 0, 0.5, 1, 0.5)
frameSizeBind(AC, "k", 0, 0, 1, 0.5)

frameSizeBind(AC, ",", 0, 0.0, 0.5, 0.5)
frameSizeBind(AC, "m", 0, 0.5, 0.5, 0.5)
frameSizeBind(AC, ".", 0.5, 0.0, 0.5, 0.5)
frameSizeBind(AC, "/", 0.5, 0.5, 0.5, 0.5)

frameResizeBind(ACS, "-", 0, -0.1)
frameResizeBind(ACS, "=", 0.0, 0.1)
frameResizeBind(AC, "-", -0.1, 0)
frameResizeBind(AC, "=", 0.1, 0)

hs.hotkey.bind(AC, "s", function()
	local win = hs.window.focusedWindow()
	win:moveToScreen(win:screen():next())
end)

hs.hotkey.bind(AC, "c", function()
	local win = hs.window.focusedWindow()
	-- center the window on the current screen
	local screenFrame = win:screen():frame()
	local windowFrame = win:frame()

	windowFrame.x = screenFrame.x + (screenFrame.w - windowFrame.w) / 2
	windowFrame.y = screenFrame.y + (screenFrame.h - windowFrame.h) / 2
	win:setFrame(windowFrame)
end)

hs.hotkey.bind(AC, "f", function()
	local win = hs.window.focusedWindow()
	-- center the window on the current screen
	local screenFrame = win:screen():frame()
	local windowFrame = win:frame()

	local win_size_is_maxed = screenFrame.w == windowFrame.w and (0 == windowFrame.x or screenFrame.x == windowFrame.x) 

	if win_size_is_maxed then
		windowFrame.w = screenFrame.w * 0.5
		windowFrame.h = screenFrame.h * 0.5
		windowFrame.x = screenFrame.x + (screenFrame.w - windowFrame.w) / 2
		windowFrame.y = screenFrame.y + (screenFrame.h - windowFrame.h) / 2
	else
		windowFrame.w = screenFrame.w
		windowFrame.h = screenFrame.h
		windowFrame.x = screenFrame.x
		windowFrame.y = screenFrame.y
	end
	win:setFrame(windowFrame)
end)

-----------------------------------------------------------
-- 2. Intercept PLAY/PAUSE media-key presses
-----------------------------------------------------------
local playTap = hs.eventtap
	.new({ hs.eventtap.event.types.systemDefined }, function(e)
		local sk = e:systemKey()
		if not (sk and sk.key == "PLAY" and sk.down) then
			return false
		end

    local stremio = hs.application.get("stremio")

		if stremio then
			local prev = hs.application.frontmostApplication()
			stremio:activate() -- bring Stremio front

			-- wait a tick so the web-view has focus, then send ␠
			hs.timer.doAfter(0.05, function()
				hs.eventtap.keyStroke({}, "space") -- play/pause
				if prev and prev ~= stremio then
					prev:activate()
				end
			end)

			return true -- swallow: don’t let macOS handle media key
		end

		return false -- different last-audio app → let OS handle it
	end)
	:start()
