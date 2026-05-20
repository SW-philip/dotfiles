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
        s=$(jq -r ".rotation_lock.${bucket}[]?" "$SNARK_FILE" 2>/dev/null | shuf -n1 || true)
        [[ -n "$s" && "$s" != "null" ]] && { echo "$s"; return; }
    fi
    echo "$fallback"
}

is_locked() {
    ! systemctl --user is-active --quiet niri-rotation.service 2>/dev/null
}

if [[ "$CMD" == "toggle" ]]; then
    if is_locked; then
        systemctl --user start niri-rotation.service
        notify-send "Rotation" "Auto-rotation enabled" -i display
    else
        systemctl --user stop niri-rotation.service
        notify-send "Rotation" "Rotation locked" -i display
    fi
    exit 0
fi

if is_locked; then
    TOOLTIP=$(printf "<span foreground='${GOLD}'>Rotation: locked</span>\n<span foreground='${SUBTLE}'>Click to enable auto-rotation</span>\n<span foreground='${SUBTLE}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$(snark_for locked 'Orientation frozen.')")
    jq -nc --arg t "󰘸" \
        --arg tooltip "$TOOLTIP" \
        '{text:$t, tooltip:$tooltip, class:"locked"}'
else
    TOOLTIP=$(printf "<span foreground='${FOAM}'>Rotation: auto</span>\n<span foreground='${SUBTLE}'>Click to lock rotation</span>\n<span foreground='${SUBTLE}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$(snark_for unlocked 'Orientation follows gravity.')")
    jq -nc --arg t "󰔃" \
        --arg tooltip "$TOOLTIP" \
        '{text:$t, tooltip:$tooltip, class:"unlocked"}'
fi
