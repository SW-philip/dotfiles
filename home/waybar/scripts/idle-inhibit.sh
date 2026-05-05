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
        s=$(jq -r ".idle_inhibit.${bucket}[]?" "$SNARK_FILE" 2>/dev/null | shuf -n1 || true)
        [[ -n "$s" && "$s" != "null" ]] && { echo "$s"; return; }
    fi
    echo "$fallback"
}

is_active() {
    systemctl --user is-active --quiet hypridle.service 2>/dev/null
}

if [[ "$CMD" == "toggle" ]]; then
    if is_active; then
        systemctl --user stop hypridle.service
        notify-send "Idle" "Screen lock inhibited" -i display
    else
        systemctl --user start hypridle.service
        notify-send "Idle" "Screen lock enabled" -i display
    fi
    exit 0
fi

if is_active; then
    TOOLTIP=$(printf "<span foreground='${FOAM}'>Screen lock: active</span>\n<span foreground='${SUBTLE}'>Click to inhibit</span>\n<span foreground='${MUTED}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$(snark_for active 'Hypridle watching.')")
    jq -nc --arg t "󰒲" \
        --arg tooltip "$TOOLTIP" \
        '{text:$t, tooltip:$tooltip, class:"active"}'
else
    TOOLTIP=$(printf "<span foreground='${MUTED}'>Screen lock: inhibited</span>\n<span foreground='${SUBTLE}'>Click to re-enable</span>\n<span foreground='${MUTED}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$(snark_for inhibited 'Screen lock dismissed.')")
    jq -nc --arg t "󰅶" \
        --arg tooltip "$TOOLTIP" \
        '{text:$t, tooltip:$tooltip, class:"inhibited"}'
fi
