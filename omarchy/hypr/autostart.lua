-- Extra autostart processes.

-- vicinae: Raycast-like launcher daemon; bound to Alt+Space via toggle.
-- Also handles clipboard history via deeplink (see bindings.lua).
o.exec_on_start("vicinae server")

-- Boot layout restore lives in hypr/layout.lua (LayoutRR), which hooks
-- hyprland.start itself.
