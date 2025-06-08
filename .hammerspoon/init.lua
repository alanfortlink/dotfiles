hs.hotkey.bind({ "alt", "ctrl" }, "r", function()
	hs.reload()
end)

local AC = { "alt", "ctrl" }
local ACS = { "alt", "ctrl", "shift" }

local setFrameSize = function(xf, yf, wf, hf, key)
	local win = hs.window.focusedWindow()
	local sf = win:screen():frame()

	win:setFrame({
		x = sf.x + sf.w * xf, -- <-- add the screen offset
		y = sf.y + sf.h * yf,
		w = sf.w * wf,
		h = sf.h * hf,
	})
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
frameSizeBind(AC, "f", 0, 0, 1, 1)

frameResizeBind(ACS, "-", 0, -0.1)
frameResizeBind(ACS, "=", 0.0, 0.1)
frameResizeBind(AC, "-", -0.1, 0)
frameResizeBind(AC, "=", 0.1, 0)

hs.hotkey.bind(AC, "s", function()
	local win = hs.window.focusedWindow()
	win:moveToScreen(win:screen():next())
end)

hs.hotkey.bind(AC, "c", function()
	local chrome = hs.application.launchOrFocus("Google Chrome")
  -- send it to the main screen
  chrome:mainWindow():moveToScreen(hs.screen.mainScreen())
end)
