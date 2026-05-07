#!/usr/bin/env bash
set -euo pipefail

SNARK_FILE="$HOME/.config/waybar/snark.json"
# shellcheck source=/dev/null
source "$HOME/.config/waybar/palette.sh"
HWMON=""
for d in /sys/class/hwmon/hwmon*; do
  if [[ "$(cat "$d/name" 2>/dev/null || true)" == "coretemp" ]]; then
    HWMON="$d"
    break
  fi
done

if [[ -z "$HWMON" ]]; then
  jq -nc '{text: " --", tooltip: "CPU sensors unavailable", class: "missing"}'
  exit 0
fi

temps=()
for f in "$HWMON"/temp*_input; do
  v=$(cat "$f" 2>/dev/null || true)
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    temps+=( $((v/1000)) )
  fi
done

if (( ${#temps[@]} == 0 )); then
  jq -nc '{text: " --", tooltip: "CPU sensors unreadable", class: "missing"}'
  exit 0
fi

TEMP=0
for t in "${temps[@]}"; do
  (( t > TEMP )) && TEMP=$t
done

if   (( TEMP < 50 )); then STATE="cool"
elif (( TEMP < 70 )); then STATE="warm"
elif (( TEMP < 85 )); then STATE="hot"
else                       STATE="critical"
fi

SNARK="Thermal status nominal."
if [[ -f "$SNARK_FILE" ]] && command -v jq >/dev/null; then
  snark=$(jq -r ".cpu_temp.${STATE}[]?" "$SNARK_FILE" 2>/dev/null | shuf -n1 || true)
  [[ -n "$snark" && "$snark" != "null" ]] && SNARK="$snark"
fi

case "$STATE" in
  cool)     TEMP_COLOR="$FOAM" ;;
  warm)     TEMP_COLOR="$GOLD" ;;
  hot)      TEMP_COLOR="$ROSE" ;;
  critical) TEMP_COLOR="$LOVE" ;;
esac

TEXT=" ${TEMP}°C"
TOOLTIP=$(printf "<span foreground='${SUBTLE}'>CPU:</span> <span foreground='${TEMP_COLOR}'>%s°C</span>\n<span foreground='${SUBTLE}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$TEMP" "$SNARK")

jq -nc \
  --arg text "$TEXT" \
  --arg tooltip "$TOOLTIP" \
  --arg class "$STATE" \
  '{text: $text, tooltip: $tooltip, class: $class}'
