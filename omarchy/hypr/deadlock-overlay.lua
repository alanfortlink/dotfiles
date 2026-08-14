-- Deadlock build overlay -- floating, pinned, never steals focus.
-- Class comes from the GTK app-id "dev.local.deadlock.overlay".
o.window("^(dev\\.local\\.deadlock\\.overlay)$", {
  float = true,
  pin = true,
  no_initial_focus = true,
  rounding = 10,
  move = "(monitor_w-window_w-40) (monitor_h*0.05)",
})

-- ALT+F11 = show/hide,  ALT+F12 = fuzzy hero picker  (drag with SUPER + left-mouse)
-- ALT+F9 / ALT+F10 = previous / next build (cycle the top community builds)
-- ALT+F8 = expand/collapse full ability descriptions
o.bind("ALT + F11", "Deadlock overlay toggle", "~/deadlock-overlay/dlctl toggle")
o.bind("ALT + F12", "Deadlock hero picker", "~/deadlock-overlay/dlctl pick")
o.bind("ALT + F9", "Deadlock previous build", "~/deadlock-overlay/dlctl prev")
o.bind("ALT + F10", "Deadlock next build", "~/deadlock-overlay/dlctl next")
o.bind("ALT + F8", "Deadlock build info", "~/deadlock-overlay/dlctl info")
