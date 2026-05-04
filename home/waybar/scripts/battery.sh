#!/usr/bin/env bash
set -euo pipefail

BAT_PATH="/sys/class/power_supply/BAT1"
SNARK_FILE="$HOME/.config/waybar/snark.json"
PALETTE_FILE="$HOME/.config/waybar/palette.sh"

if [[ -f "$PALETTE_FILE" ]]; then
    source "$PALETTE_FILE"
else
    MUTED="#6e6a86"; IRIS="#c4a7e7"
fi

if [[ -d "$BAT_PATH" ]]; then
    status=$(cat "$BAT_PATH/status")
    PERCENT=$(cat "$BAT_PATH/capacity")

    if [ "$PERCENT" -eq 100 ]; then bucket="full"
    elif [ "$PERCENT" -ge 20 ]; then bucket="high"
    else bucket="low"; fi

    case $status in
        "Charging") GLYPH="󰂄" ;;
        "Full")     GLYPH="󰂄" ;;
        *)          GLYPH="󰁹" ;;
    esac
else
    PERCENT="100"; bucket="full"; GLYPH="󰚥"; status="AC"
fi

# AC = anything not actively discharging
if [[ "$status" != "Discharging" ]]; then
    BAT_TEXT="${GLYPH} ∞"
else
    BAT_TEXT="${GLYPH} ${PERCENT}%"
fi

snark="System operational."
if [[ -f "$SNARK_FILE" ]]; then
    snark=$(jq -r ".battery.${bucket} | .[]" "$SNARK_FILE" | shuf -n1 || echo "System operational.")
fi

TOOLTIP="<span foreground='${MUTED}'>Status:</span> ${status}
<span foreground='${MUTED}'>Charge:</span> ${PERCENT}%
<span foreground='${MUTED}'>────────────────────</span>
<span foreground='${IRIS}'>${snark}</span>"

jq -nc \
  --arg text "$BAT_TEXT" \
  --arg tooltip "$TOOLTIP" \
  --arg class "$bucket" \
  '{ text: $text, tooltip: $tooltip, class: $class }'
