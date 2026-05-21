#!/usr/bin/env bash
set -euo pipefail

BAT_PATH="/sys/class/power_supply/BAT1"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sleep-drain"
CMD="${1:-}"

mkdir -p "$CACHE_DIR"

# Called by systemd ExecStart (pre-sleep)
if [[ "$CMD" == "pre" ]]; then
    printf '%s\n%s\n' \
        "$(cat "$BAT_PATH/energy_now" 2>/dev/null || echo 0)" \
        "$(date +%s)" \
        > "$CACHE_DIR/pre"
    exit 0
fi

# Called by systemd ExecStop (post-wake)
if [[ "$CMD" == "post" ]]; then
    printf '%s\n%s\n' \
        "$(cat "$BAT_PATH/energy_now" 2>/dev/null || echo 0)" \
        "$(date +%s)" \
        > "$CACHE_DIR/post"
    pkill -RTMIN+2 waybar 2>/dev/null || true
    exit 0
fi

# Display mode — no args
# shellcheck source=/dev/null
source "$HOME/.config/waybar/palette.sh"

SNARK_FILE="$HOME/.config/waybar/snark.json"

snark_for() {
    local bucket="$1" fallback="${2:-}"
    if [[ -f "$SNARK_FILE" ]] && command -v jq >/dev/null; then
        local s
        s=$(jq -r ".sleep_drain.${bucket}[]?" "$SNARK_FILE" 2>/dev/null | shuf -n1 || true)
        [[ -n "$s" && "$s" != "null" ]] && echo "$s" && return
    fi
    echo "$fallback"
}

if [[ ! -d "$BAT_PATH" ]]; then
    jq -nc '{text:"", tooltip:"", class:"hidden"}'
    exit 0
fi

PRE="$CACHE_DIR/pre"
POST="$CACHE_DIR/post"

no_data() {
    local msg="$1"
    jq -nc \
        --arg text "󰒲 --" \
        --arg tooltip "$(printf "<span foreground='${SUBTLE}'>Sleep drain</span>\n<span foreground='${SUBTLE}'>%s</span>" "$msg")" \
        --arg class "unknown" \
        '{text:$text, tooltip:$tooltip, class:$class}'
}

if [[ ! -f "$PRE" || ! -f "$POST" ]]; then
    no_data "No data yet — accumulates after first sleep"; exit 0
fi

pre_energy=$(sed -n '1p' "$PRE")
pre_time=$(sed -n '2p'   "$PRE")
post_energy=$(sed -n '1p' "$POST")
post_time=$(sed -n '2p'   "$POST")

if (( post_time <= pre_time )); then
    no_data "Waiting for next sleep cycle"; exit 0
fi

energy_full=$(cat "$BAT_PATH/energy_full" 2>/dev/null || echo 1)
drain=$(( pre_energy - post_energy ))
sleep_secs=$(( post_time - pre_time ))
sleep_h=$(( sleep_secs / 3600 ))
sleep_m=$(( (sleep_secs % 3600) / 60 ))

drain_pct=$(awk  "BEGIN{printf \"%.1f\", ($drain  * 100) / $energy_full}")
drain_hr=$(awk   "BEGIN{printf \"%.1f\", ($drain  * 100 * 3600) / ($energy_full * $sleep_secs)}")

is_neg=$(awk "BEGIN{print ($drain < 0) ? 1 : 0}")
if [[ "$is_neg" == "1" ]]; then
    abs_pct=$(awk "BEGIN{printf \"%.1f\", -($drain_pct)}")
    display="+${abs_pct}%"
    state="charging"; COLOR="$FOAM"
else
    display="-${drain_pct}%"
    if   awk "BEGIN{exit !($drain_pct > 8)}"; then state="critical"; COLOR="$LOVE"
    elif awk "BEGIN{exit !($drain_pct > 4)}"; then state="warn";     COLOR="$GOLD"
    elif awk "BEGIN{exit !($drain_pct > 1)}"; then state="ok";       COLOR="$TEXT"
    else                                           state="great";    COLOR="$FOAM"
    fi
fi

BAR_TEXT="󰒲 <span foreground='${COLOR}'>${display}</span>"
TOOLTIP=$(printf \
    "<span foreground='${SUBTLE}'>Sleep drain</span>\n<span foreground='${SUBTLE}'>Duration:</span> <span foreground='${TEXT}'>%dh %dm</span>\n<span foreground='${SUBTLE}'>Drained:</span>  <span foreground='${COLOR}'>%s</span>\n<span foreground='${SUBTLE}'>Rate:</span>     <span foreground='${SUBTLE}'>%s%%/hr</span>" \
    "$sleep_h" "$sleep_m" "$display" "$drain_hr")
TOOLTIP+=$'\n'"<span foreground='${SUBTLE}'>────────────────────</span>"$'\n'"<span foreground='${IRIS}'>$(snark_for "$state" 'Sleep metrics available.')</span>"

jq -nc \
    --arg text    "$BAR_TEXT" \
    --arg tooltip "$TOOLTIP" \
    --arg class   "$state" \
    '{text:$text, tooltip:$tooltip, class:$class}'
