#!/usr/bin/env bash
# ~/.config/waybar/scripts/weather_toggle.sh

STATE_FILE="$HOME/.cache/weather_state"

# create if missing
[ -f "$STATE_FILE" ] || echo "default" > "$STATE_FILE"

# toggle between 'default' and 'forecast'
if grep -q "forecast" "$STATE_FILE" 2>/dev/null; then
    echo "default" > "$STATE_FILE"
else
    echo "forecast" > "$STATE_FILE"
fi

# refresh waybar instantly
pkill -SIGUSR2 waybar 2>/dev/null
