#!/usr/bin/env bash
# Waybar ProtonVPN WireGuard status indicator

PALETTE="$HOME/.config/waybar/palette.sh"
# shellcheck source=/dev/null
source "$PALETTE" 2>/dev/null || true

PINE="${PINE:-#31748f}"
MUTED="${MUTED:-#6e6a86}"
LOVE="${LOVE:-#eb6f92}"
IRIS="${IRIS:-#c4a7e7}"

ICON_ON="󰖂"
ICON_OFF="󰦞"

SNARK_FILE="$HOME/.config/waybar/snark.json"

snark_for() {
    local bucket="$1" fallback="${2:-}"
    if [[ -f "$SNARK_FILE" ]] && command -v jq >/dev/null; then
        local s
        s=$(jq -r ".protonvpn.${bucket}[]?" "$SNARK_FILE" 2>/dev/null | shuf -n1 || true)
        [[ -n "$s" && "$s" != "null" ]] && echo "$s" && return
    fi
    echo "$fallback"
}

if systemctl is-active --quiet wg-quick-protonvpn.service 2>/dev/null; then
    TOOLTIP=$(printf "<span foreground='${PINE}'>ProtonVPN Connected</span>\n<span foreground='${MUTED}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$(snark_for on 'Traffic disguised.')")
    jq -nc --arg text "$ICON_ON" --arg tooltip "$TOOLTIP" --arg class "vpn-on" \
        '{text:$text, tooltip:$tooltip, class:$class}'
else
    TOOLTIP=$(printf "<span foreground='${MUTED}'>ProtonVPN Off</span>\n<span foreground='${MUTED}'>Click to connect</span>\n<span foreground='${MUTED}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$(snark_for off 'Exposed to the open internet.')")
    jq -nc --arg text "$ICON_OFF" --arg tooltip "$TOOLTIP" --arg class "vpn-off" \
        '{text:$text, tooltip:$tooltip, class:$class}'
fi
