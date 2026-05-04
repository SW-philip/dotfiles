#!/usr/bin/env bash
# Toggle the volume popup window.
# First click: opens a ghostty window running volume-control.sh
# Second click: kills the running volume-control.sh, which closes the window.

SCRIPTS="${HOME}/.config/waybar/scripts"

if pkill -f "volume-control.sh" 2>/dev/null; then
    exit 0
fi

exec ghostty \
    --class=volume-popup \
    --title="Volume" \
    -e "${SCRIPTS}/volume-control.sh"
