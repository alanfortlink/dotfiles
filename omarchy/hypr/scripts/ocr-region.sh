#!/usr/bin/env bash
# Select a screen region, OCR it, copy text to clipboard.
set -euo pipefail

geom=$(slurp) || exit 0
text=$(grim -g "$geom" - | tesseract - - 2>/dev/null)

if [[ -n "${text//[$' \t\n']/}" ]]; then
  printf '%s' "$text" | wl-copy
  notify-send "OCR" "Copied to clipboard"
else
  notify-send "OCR" "No text detected"
fi
