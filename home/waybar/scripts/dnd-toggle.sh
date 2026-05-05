#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"
SNARK_FILE="$HOME/.config/waybar/snark.json"
# shellcheck source=/dev/null
source "$HOME/.config/waybar/palette.sh"

snark_for() {
    local bucket="$1" fallback="$2"
    if [[ -f "$SNARK_FILE" ]] && command -v jq >/dev/null; then
        local s
        s=$(jq -r ".dnd.${bucket}[]?" "$SNARK_FILE" 2>/dev/null | shuf -n1 || true)
        [[ -n "$s" && "$s" != "null" ]] && { echo "$s"; return; }
    fi
    echo "$fallback"
}

is_dnd() {
    makoctl mode 2>/dev/null | grep -q "do-not-disturb"
}

if [[ "$CMD" == "toggle" ]]; then
    if is_dnd; then
        makoctl mode -r do-not-disturb
        notify-send "Notifications" "Do Not Disturb off"
    else
        makoctl mode -a do-not-disturb
    fi
    exit 0
fi

if is_dnd; then
    TOOLTIP=$(printf "<span foreground='${MUTED}'>Do Not Disturb:</span> <span foreground='${GOLD}'>on</span>\n<span foreground='${SUBTLE}'>Click to disable</span>\n<span foreground='${MUTED}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$(snark_for on 'The world will wait.')")
    jq -nc --arg t "󰂛" \
        --arg tooltip "$TOOLTIP" \
        '{text:$t, tooltip:$tooltip, class:"dnd"}'
else
    TOOLTIP=$(printf "<span foreground='${MUTED}'>Notifications:</span> <span foreground='${FOAM}'>on</span>\n<span foreground='${SUBTLE}'>Click to enable DND</span>\n<span foreground='${MUTED}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$(snark_for off 'Notifications flowing.')")
    jq -nc --arg t "󰂚" \
        --arg tooltip "$TOOLTIP" \
        '{text:$t, tooltip:$tooltip, class:"active"}'
fi
