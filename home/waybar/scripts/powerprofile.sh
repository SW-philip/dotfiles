#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"
current=$(powerprofilesctl get 2>/dev/null || echo "balanced")

SNARK_FILE="$HOME/.config/waybar/snark.json"
# shellcheck source=/dev/null
source "$HOME/.config/waybar/palette.sh"

if [[ -n "$CMD" ]]; then
    # Cycle through only profiles that are actually available on this hardware
    mapfile -t available < <(powerprofilesctl list 2>/dev/null | awk '/^[* ] ?[a-z]/ { gsub(/[* :]/, ""); print $1 }')
    # Preferred order: power-saver → balanced → performance → power-saver
    ordered=(power-saver balanced performance)
    next="balanced"
    for i in "${!ordered[@]}"; do
        if [[ "${ordered[$i]}" == "$current" ]]; then
            for j in $(seq 1 ${#ordered[@]}); do
                candidate="${ordered[$(( (i + j) % ${#ordered[@]} ))]}"
                if printf '%s\n' "${available[@]}" | grep -qx "$candidate"; then
                    next="$candidate"
                    break
                fi
            done
            break
        fi
    done
    if ! powerprofilesctl set "$next" 2>/dev/null; then
        # EPP write can fail if cpu governor is stuck in "performance" mode.
        # After nrs adds powerManagement.cpuFreqGovernor = "powersave" this should
        # not happen, but catch it gracefully rather than killing the toggle.
        notify-send -u normal "Power Profile" \
            "Failed to set $next — EPP locked (governor stuck?)" 2>/dev/null || true
    fi
    exit 0
fi

case "$current" in
    power-saver)  icon="󱐌"; class="power-saver"; PROFILE_COLOR="$FOAM"   ;;
    balanced)     icon="󰈐"; class="balanced";    PROFILE_COLOR="$SUBTLE" ;;
    performance)  icon="󱐋"; class="performance"; PROFILE_COLOR="$LOVE"   ;;
    *)            icon="?";  class="unknown";     PROFILE_COLOR="$TEXT"   ;;
esac
SNARK="Click to cycle profiles."
bucket="${current//-/_}"
if [[ -f "$SNARK_FILE" ]] && command -v jq >/dev/null; then
    snark=$(jq -r ".power_profile.${bucket}[]?" "$SNARK_FILE" 2>/dev/null | shuf -n1 || true)
    [[ -n "$snark" && "$snark" != "null" ]] && SNARK="$snark"
fi

TOOLTIP=$(printf "<span foreground='${MUTED}'>Profile:</span> <span foreground='${PROFILE_COLOR}'>%s</span>\n<span foreground='${SUBTLE}'>Click to cycle</span>\n<span foreground='${MUTED}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$current" "$SNARK")

jq -nc \
    --arg text "$icon" \
    --arg tooltip "$TOOLTIP" \
    --arg class "$class" \
    '{text:$text, tooltip:$tooltip, class:$class}'
