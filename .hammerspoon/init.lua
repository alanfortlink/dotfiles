---@diagnostic disable: undefined-global
hs.hotkey.bind({ "alt", "ctrl" }, "r", function()
	hs.alert.show("Reloading Hammerspoon config...")
	hs.timer.doAfter(0.5, function()
		hs.reload()
	end)
end)

local A = { "alt" }
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

-- when f8 is pressed
hs.hotkey.bind({}, "f8", function()
	local stremio = hs.application.get("stremio")

	if stremio then
		local prev = hs.application.frontmostApplication()
		stremio:activate()

		-- wait a tick so the web-view has focus, then send ␠
		hs.timer.doAfter(0.01, function()
			hs.eventtap.keyStroke({}, "space")
			if prev and prev ~= stremio then
				prev:activate()
			end
		end)

		return true
	end

	-- send play/pause key
	hs.eventtap.event.newSystemKeyEvent("PLAY", true):post()
	hs.eventtap.event.newSystemKeyEvent("PLAY", false):post()

	return true
end)

-- when f6 is pressed:
-- 1. Set the terminal (ghostty) window to full height, 60% width
-- 2. Move it to the left side of the screen
-- 3. Bring up two Simulators and position them with equal size on the right side of the screen (last 40%)
-- 4. Focus the terminal window

hs.hotkey.bind({}, "f6", function()
	local terminal = hs.application.get("iTerm2")
	if not terminal then
		terminal = hs.application.get("iTerm")
	end

	if terminal then
		local screenFrame = hs.screen.mainScreen():frame()
		local terminalFrame = {
			x = screenFrame.x,
			y = screenFrame.y,
			w = screenFrame.w * 0.6,
			h = screenFrame.h,
		}
		terminal:mainWindow():setFrame(terminalFrame)

		-- launch or focus iphone 16 pro simulator
		local simulatorApp = hs.application.launchOrFocus("Simulator")

		if not simulatorApp then
			return
		end

		local sim = hs.application.get("Simulator")
		if not sim then
			sim = hs.application.get("simulator")
		end

		if not sim then
			return
		end

		local numWindows = #sim:allWindows()
		if numWindows < 2 then
			hs.timer.doAfter(0.2, function()
				sim:selectMenuItem({ "File", "Open Simulator", "iOS 18.0", "iPhone 16 Pro" })
				sim:selectMenuItem({ "File", "Open Simulator", "iOS 17.5", "iPhone 15 Pro" })
			end)
			return
		end

		-- get by title
		local iphone15 = sim:findWindow("iPhone 15 Pro")
		local iphone16 = sim:findWindow("iPhone 16 Pro")

		if not iphone15 or not iphone16 then
			return
		end

		local iphone15Frame = iphone15:frame()
		local iphone16Frame = iphone16:frame()

		hs.timer.doAfter(0.2, function()
			iphone15Frame.x = screenFrame.x + screenFrame.w * 0.6
			iphone15Frame.y = screenFrame.y
			iphone15Frame.w = screenFrame.w * 0.2
			iphone15Frame.h = screenFrame.h * 0.5

			iphone16Frame.x = screenFrame.x + screenFrame.w * 0.8
			iphone16Frame.y = screenFrame.y
			iphone16Frame.w = screenFrame.w * 0.2
			iphone16Frame.h = screenFrame.h * 0.5

			iphone15:setFrame(iphone15Frame)
			iphone16:setFrame(iphone16Frame)
		end)

		hs.timer.doAfter(0.2, function()
			-- centralize vertically
			iphone15Frame.y = screenFrame.y + (screenFrame.h - iphone15Frame.h) / 4
			iphone16Frame.y = screenFrame.y + (screenFrame.h - iphone16Frame.h) / 4

			iphone15:setFrame(iphone15Frame)
			iphone16:setFrame(iphone16Frame)
		end)

		hs.timer.doAfter(0.2, function()
			terminal:mainWindow():focus()
			hs.eventtap.keyStroke({ "ctrl" }, "b")
			hs.eventtap.keyStroke({}, "2")
		end)
	end
end)

hs.hotkey.bind({}, "f7", function()
	local terminal = hs.application.get("iTerm2")
	if not terminal then
		terminal = hs.application.get("iTerm")
	end

	if terminal then
		terminal:mainWindow():focus()

		hs.timer.doAfter(0.1, function()
			local screenFrame = hs.screen.mainScreen():frame()
			local terminalFrame = terminal:mainWindow():frame()

			terminalFrame.w = screenFrame.w

			terminal:mainWindow():setFrame(terminalFrame)

			hs.eventtap.keyStroke({ "ctrl" }, "b")
			hs.eventtap.keyStroke({}, "1")
		end)
	end
end)

hs.hotkey.bind({}, "f5", function()
	-- kill simulators
	local sim = hs.application.get("Simulator")
	if sim then
		sim:kill()
	end
end)
