#!/bin/bash
socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" |
  while IFS= read -r line; do
    case "$line" in
      activelayout\>\>*)
        layout="${line##*,}"
        notify-send -t 1000 -h string:x-canonical-private-synchronous:kb-layout "⌨  $layout"
        ;;
    esac
  done
