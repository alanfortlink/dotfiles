-- Extra autostart processes.

-- vicinae: Raycast-like launcher daemon; bound to Alt+Space via toggle.
-- Also handles clipboard history via deeplink (see bindings.lua).
o.exec_on_start("vicinae server")

-- Boot layout restore lives in hypr/layout.lua (LayoutRR), which hooks
-- hyprland.start itself.

-- === Switch to DMS (DankMaterialShell) ===
-- Stops the Omarchy shell supervisor (which takes the Omarchy bar/shell with
-- it), then launches DMS. Delete this block (plus hypr/dms.lua, the DMS
-- binds in bindings.lua, and hypr/dms/) to go back to the Omarchy shell.
hl.on("hyprland.start", function()
  hl.exec_cmd("bash -c 'sleep 2; pkill -f \"[o]marchy-launch-shell\"; sleep 1; exec dms run' >/dev/null 2>&1 &")
end)
