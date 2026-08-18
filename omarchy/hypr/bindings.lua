-- Personal keybinding overrides. Omarchy 4 defaults stay untouched unless
-- explicitly unbound here first.
--
-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- === hjkl window control ===
--   ALT + hjkl                  -> move focus
--   ALT + SHIFT + hjkl          -> resize active window (intuitive direction)
--   SUPER + ALT + hjkl          -> swap with the adjacent neighbor
--   SUPER + CTRL + SHIFT + hjkl -> merge: re-parent across split boundaries

-- hypr-mux-focus: if the active window hosts herdr or tmux and a pane exists
-- in that direction, focus the pane; otherwise plain Hyprland movefocus.
o.bind("ALT + H", "Focus left", "hypr-mux-focus l")
o.bind("ALT + J", "Focus down", "hypr-mux-focus d")
o.bind("ALT + K", "Focus up", "hypr-mux-focus u")
o.bind("ALT + L", "Focus right", "hypr-mux-focus r")

-- hypr-resize-intuitive flips the sign when dwindle would otherwise resize
-- the wrong edge (active in right subtree of its parent H-split).
o.bind("ALT + SHIFT + H", "Resize narrower", "hypr-resize-intuitive narrower 100", { repeating = true })
o.bind("ALT + SHIFT + J", "Resize taller", "hypr-resize-intuitive taller 100", { repeating = true })
o.bind("ALT + SHIFT + K", "Resize shorter", "hypr-resize-intuitive shorter 100", { repeating = true })
o.bind("ALT + SHIFT + L", "Resize wider", "hypr-resize-intuitive wider 100", { repeating = true })

-- Swap. SUPER+ALT+K default (tmux keybindings) moves to CTRL+SUPER+ALT+K.
hl.unbind("SUPER + ALT + K")
o.bind("SUPER + ALT + H", "Swap left", hl.dsp.window.swap({ direction = "l" }))
o.bind("SUPER + ALT + J", "Swap down", hl.dsp.window.swap({ direction = "d" }))
o.bind("SUPER + ALT + K", "Swap up", hl.dsp.window.swap({ direction = "u" }))
o.bind("SUPER + ALT + L", "Swap right", hl.dsp.window.swap({ direction = "r" }))
o.bind("CTRL + SUPER + ALT + K", "Tmux keybindings", "omarchy-menu-tmux-keybindings")

-- Merge: push the active window across a split so it becomes a sibling of
-- the neighbor's group (collapses a column/row).
o.bind("SUPER + CTRL + SHIFT + H", "Merge left", hl.dsp.window.move({ direction = "l" }))
o.bind("SUPER + CTRL + SHIFT + J", "Merge down", hl.dsp.window.move({ direction = "d" }))
o.bind("SUPER + CTRL + SHIFT + K", "Merge up", hl.dsp.window.move({ direction = "u" }))
o.bind("SUPER + CTRL + SHIFT + L", "Merge right", hl.dsp.window.move({ direction = "r" }))

-- === Fullscreen ===
o.bind("ALT + F", "Maximize (full width)", hl.dsp.window.fullscreen({ mode = "maximized" }))
-- In herdr/tmux (with >1 pane) this toggles pane zoom instead.
o.bind("ALT + Z", "Maximize / mux pane zoom", "hypr-mux-zoom")
-- Hyprland only hides the bar (top layer) when the monitor's *regular*
-- workspace has a fullscreen window — fullscreen inside a special workspace
-- keeps the bar visible. So hop the window out of its scratchpad before
-- fullscreening, and send it back (and re-show the scratchpad) on toggle off.
local fullscreen_scratch_origin = {}

local function special_visible(name)
  for _, m in ipairs(hl.get_monitors()) do
    local sw = m.active_special_workspace
    if sw and sw.name == name then
      return true
    end
  end
  return false
end

o.bind("ALT + SHIFT + F", "Full screen", function()
  local w = hl.get_active_window()
  if not w then
    return
  end

  if w.fullscreen == 2 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen" }))
    local origin = fullscreen_scratch_origin[w.address]
    if origin then
      fullscreen_scratch_origin[w.address] = nil
      hl.dispatch(hl.dsp.window.move({ workspace = origin, follow = false }))
      if not special_visible(origin) then
        hl.dispatch(hl.dsp.workspace.toggle_special(origin:gsub("^special:", "")))
      end
    end
    return
  end

  local ws = w.workspace
  if ws and ws.special then
    fullscreen_scratch_origin[w.address] = ws.name
    local target = w.monitor and w.monitor.active_workspace
    if target then
      hl.dispatch(hl.dsp.window.move({ workspace = "name:" .. target.name }))
    end
  end
  hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen" }))
end)

-- === Fill column / row ===
-- Push every window sharing the active's column (or row) into the adjacent
-- column/row, so the active fills it and everything else re-tiles on screen.
o.bind("ALT + SHIFT + C", "Fill column", "hypr-fill column")
o.bind("ALT + SHIFT + R", "Fill row", "hypr-fill row")

-- === Monitors ===
o.bind("CTRL + SHIFT + S", "Move window to next monitor", hl.dsp.window.move({ monitor = "+1", follow = true }))
-- SUPER+ALT+S was: Move window to scratchpad (omarchy default)
hl.unbind("SUPER + ALT + S")
o.bind("SUPER + ALT + S", "Move window to next monitor", hl.dsp.window.move({ monitor = "+1", follow = true }))

-- === Launcher ===
-- ALT+SPACE mirrors SUPER+SPACE and opens the Omarchy menu.
hl.unbind("ALT + SPACE")  -- was: Vicinae toggle

o.bind("ALT + SPACE", "Omarchy menu", "omarchy-menu toggle")

-- === Vicinae ===
-- Toggle moved here from ALT+SPACE.
o.bind("ALT + SHIFT + SPACE", "Vicinae", "vicinae toggle")
o.bind("ALT + SHIFT + V", "Clipboard manager (vicinae)", "vicinae deeplink vicinae://launch/clipboard/history")

-- Omarchy's default clipboard history (same action as SUPER+CTRL+V).
o.bind("SUPER + SHIFT + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")
o.bind("CTRL + SHIFT + A", "Browser tab switcher", "vicinae deeplink vicinae://launch/browser-extension/browse-tabs")
o.bind("CTRL + ALT + SPACE", "Emoji picker", "vicinae deeplink vicinae://launch/core/search-emojis")
o.bind("CTRL + ALT + F", "Fuzzy file search", "vicinae deeplink 'vicinae://launch/@sameoldlab/store.vicinae.fuzzy-files/find'")
o.bind("CTRL + ALT + M", "Now Playing", "vicinae deeplink 'vicinae://launch/@tank/now-playing/list'")
o.bind("CTRL + SHIFT + F10", "Install AUR package", "xdg-terminal-exec --app-id=org.omarchy.terminal omarchy-pkg-aur-install")

-- === Scratchpads ===
-- Pin scratchpads to the right monitor (DP-1) so focusing back to it
-- doesn't migrate/hide the special workspace.
hl.workspace_rule({ workspace = "special:scratchpad", monitor = "DP-1" })
hl.workspace_rule({ workspace = "special:scratch1", monitor = "DP-1" })
hl.workspace_rule({ workspace = "special:scratch2", monitor = "DP-1" })
hl.workspace_rule({ workspace = "special:scratch3", monitor = "DP-1" })
hl.workspace_rule({ workspace = "special:scratch4", monitor = "DP-1" })

-- togglespecialworkspace ignores the workspace monitor rule (known Hyprland
-- limitation), so focus DP-1 first before toggling.
local function toggle_scratch_on_dp1(name)
  return 'hyprctl --batch \'dispatch hl.dsp.focus({ monitor = "DP-1" }) ; dispatch hl.dsp.workspace.toggle_special("' .. name .. '")\''
end

hl.unbind("SUPER + S")
o.bind("SUPER + S", "Toggle scratchpad", toggle_scratch_on_dp1("scratchpad"))
o.bind("ALT + S", "Toggle window in/out of scratchpad", "hypr-scratchpad-out")
o.bind("CTRL + SHIFT + F1", "Scratchpad 1", toggle_scratch_on_dp1("scratch1"))
o.bind("CTRL + SHIFT + F2", "Scratchpad 2", toggle_scratch_on_dp1("scratch2"))
o.bind("CTRL + SHIFT + F3", "Scratchpad 3", toggle_scratch_on_dp1("scratch3"))
o.bind("CTRL + SHIFT + F4", "Scratchpad 4", toggle_scratch_on_dp1("scratch4"))

-- Toggle the focused window in/out of the matching scratchpad (mirrors
-- ALT+S for the default scratchpad): pressing it inside the scratchpad
-- sends the window back to the visible workspace.
o.bind("CTRL + SHIFT + ALT + F1", "Toggle window in/out of scratchpad 1", "hypr-scratchpad-out scratch1")
o.bind("CTRL + SHIFT + ALT + F2", "Toggle window in/out of scratchpad 2", "hypr-scratchpad-out scratch2")
o.bind("CTRL + SHIFT + ALT + F3", "Toggle window in/out of scratchpad 3", "hypr-scratchpad-out scratch3")
o.bind("CTRL + SHIFT + ALT + F4", "Toggle window in/out of scratchpad 4", "hypr-scratchpad-out scratch4")

-- === macOS-style ALT remaps ===
-- These must inject from a lua callback with send_key_state: exec'd injectors
-- (wtype, hyprctl sendshortcut) fire while the physical Alt is still held, and
-- a virtual keyboard can't unmerge a physically-held modifier at the seat.
-- Same pattern as omarchy's default/hypr/bindings/clipboard.lua, including the
-- down/up split that works around synthetic key state getting stuck.
local function send_once(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))

  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

local function mac(mods, key)
  return function()
    send_once(mods, key)
  end
end

local function active_is_terminal()
  local window = hl.get_active_window()

  for _, tag in ipairs(window and window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end

  return false
end

-- Ctrl+<key> normally; Ctrl+Shift+<key> in terminals, where plain Ctrl+<key>
-- is a control code (Ctrl+T/N there means new tab/window in ghostty).
local function mac_routed(key)
  return function()
    send_once(active_is_terminal() and "CTRL SHIFT" or "CTRL", key)
  end
end

-- === macOS-style quit/close ===
o.bind("ALT + Q", "Quit app (all windows)", "quit-app")
o.bind("ALT + W", "Close tab in browser / window elsewhere", function()
  local window = hl.get_active_window()
  local class = window and window.class or ""
  if class:match("chrome") or class:match("hromium") then
    send_once("CTRL", "W")
  else
    -- Closes a herdr/tmux pane when a multiplexer is active (tmux asks
    -- first if the pane is running something other than a shell).
    hl.dispatch(hl.dsp.exec_cmd("hypr-mux-close"))
  end
end)

-- Small floating confirm dialog (org.omarchy.confirm terminals).
o.window("^(org\\.omarchy\\.confirm)$", {
  float = true,
  size = "700 160",
  center = true,
})
o.bind("SUPER + Q", "Close window", hl.dsp.window.close())

-- In a terminal these open panes/tabs in herdr or tmux (local, nested or over
-- ssh), mirroring prefix+v / prefix+n / prefix+c; elsewhere they keep their
-- macOS meaning. No mux in the terminal -> new terminal window.
local function mux_or(cmd, mods, key)
  return function()
    if active_is_terminal() then
      hl.dispatch(hl.dsp.exec_cmd(cmd))
    else
      send_once(mods, key)
    end
  end
end

o.bind("ALT + N", "Split pane stacked / New window", mux_or("hypr-mux-split stacked", "CTRL", "N"))
o.bind("ALT + T", "New tab", mac_routed("T"))
o.bind("ALT + SHIFT + T", "Reopen tab", mac("CTRL SHIFT", "T"))
o.bind("ALT + R", "Reload", mac("CTRL", "R"))
o.bind("ALT + E", "Address bar", mac("CTRL", "L"))
-- Ctrl/Shift+Insert copy/paste are universal; in a terminal these are the mux
-- new-tab / split instead, so copy/paste there is ghostty's own
-- CTRL+INSERT / SHIFT+INSERT.
o.bind("ALT + C", "New tab in mux / Copy", mux_or("hypr-mux-tab", "CTRL", "Insert"))
o.bind("ALT + V", "Split pane side by side / Paste", mux_or("hypr-mux-split side", "SHIFT", "Insert"))
o.bind("ALT + X", "Cut", mac("CTRL", "X"))
-- Ctrl+1..8 = tab N, Ctrl+9 = last tab, Ctrl+0 = reset zoom.
o.bind("ALT + 1", "Tab 1", mac("CTRL", "1"))
o.bind("ALT + 2", "Tab 2", mac("CTRL", "2"))
o.bind("ALT + 3", "Tab 3", mac("CTRL", "3"))
o.bind("ALT + 4", "Tab 4", mac("CTRL", "4"))
o.bind("ALT + 5", "Tab 5", mac("CTRL", "5"))
o.bind("ALT + 6", "Tab 6", mac("CTRL", "6"))
o.bind("ALT + 7", "Tab 7", mac("CTRL", "7"))
o.bind("ALT + 8", "Tab 8", mac("CTRL", "8"))
o.bind("ALT + 9", "Tab 9", mac("CTRL", "9"))
o.bind("ALT + 0", "Reset zoom", mac("CTRL", "0"))
o.bind("ALT + A", "Select all", mac("CTRL", "A"))
-- Editing/document shortcuts: ALT -> CTRL, universal combos.
-- (Cmd+S/Save is NOT mapped: ALT+S is the scratchpad toggle. Undo and Find
-- are NOT mapped: ALT+Z and ALT+F are maximize; use the apps' native
-- Ctrl+Z / Ctrl+F.)
o.bind("ALT + SHIFT + Z", "Redo", mac("CTRL SHIFT", "Z"))
o.bind("ALT + P", "Print", mac("CTRL", "P"))
o.bind("ALT + D", "Bookmark", mac("CTRL", "D"))
o.bind("ALT + B", "Bold", mac("CTRL", "B"))
o.bind("ALT + I", "Italic", mac("CTRL", "I"))
o.bind("ALT + U", "Underline", mac("CTRL", "U"))
o.bind("ALT + M", "Insert link", mac("CTRL", "K"))
o.bind("ALT + comma", "Preferences", mac("CTRL", "comma"))
o.bind("ALT + equal", "Zoom in", mac("CTRL", "equal"))
o.bind("ALT + minus", "Zoom out", mac("CTRL", "minus"))

-- === Layout save ===
-- Snapshot the current window layout; restored on next login (hypr/layout.lua).
o.bind("CTRL + ALT + L", "Save layout", function() LayoutRR.save() end)

-- === Capture ===
o.bind("ALT + SHIFT + S", "Region screenshot to clipboard", "omarchy capture screenshot region copy")
o.bind("ALT + SHIFT + G", "Caption GIF", "gif-captioner")
o.bind("ALT + SHIFT + O", "OCR region", "~/.config/hypr/scripts/ocr-region.sh")

-- === Voice: Ask Claude + dictation ===
-- F8 = toggle Ask Claude with /omarchy skill prepended. Tap to start, tap
-- again to stop + launch. SHIFT+F8 = plain Ask Claude voice toggle.
o.bind("F8", "Ask Claude voice omarchy toggle", "ask-claude-voice-toggle /omarchy")
o.bind("SHIFT + F8", "Ask Claude (voice) toggle", "ask-claude-voice-toggle")

-- F9 = toggle dictation (en); replaces stock push-to-talk dictation. Wrapper
-- registers a transient ESC cancel binding while recording.
hl.unbind("F9")
o.bind("F9", "Toggle dictation", "voxtype-toggle en")
o.bind("SHIFT + F9", "Toggle dictation pt-br", "voxtype-toggle pt")
o.bind("CTRL + F9", "Dictate and send", "voxtype-toggle-enter en")

o.window("^(claude-ask)$", {
  float = true,
  size = "1200 800",
  center = true,
})
