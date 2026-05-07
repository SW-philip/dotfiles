#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "$HOME/.config/waybar/palette.sh"

built=$(stat -c %Y /run/current-system 2>/dev/null || echo 0)
now=$(date +%s)
elapsed=$(( now - built ))
days=$(( elapsed / 86400 ))
hours=$(( elapsed / 3600 ))
rem_h=$(( hours % 24 ))

built_date=$(date -d "@$built" "+%b %d, %H:%M" 2>/dev/null || echo "unknown")

if   (( days >= 14 )); then state="stale";  COLOR="$LOVE";   label="${days}d"
elif (( days >= 7  )); then state="aging";  COLOR="$GOLD";   label="${days}d"
elif (( days >= 1  )); then state="ok";     COLOR="$SUBTLE"; label="${days}d"
else                        state="fresh";  COLOR="$FOAM";   label="${hours}h"
fi

BAR_TEXT="󱄅 ${label}"
TOOLTIP=$(printf \
    "<span foreground='${SUBTLE}'>Last rebuild:</span> <span foreground='${TEXT}'>%s</span>\n<span foreground='${SUBTLE}'>Age:</span>          <span foreground='${COLOR}'>%dd %dh</span>" \
    "$built_date" "$days" "$rem_h")

jq -nc \
    --arg text    "$BAR_TEXT" \
    --arg tooltip "$TOOLTIP" \
    --arg class   "$state" \
    '{text:$text, tooltip:$tooltip, class:$class}'
