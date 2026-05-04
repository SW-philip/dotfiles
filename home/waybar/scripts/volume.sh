#!/usr/bin/env bash
set -uo pipefail

JBL_MAC="90_F2_60_B3_88_9F"

# ------------------------------------------------------------
# Resolve the best available audio sink by node name.
# Priority: JBL (by MAC in node name) → any BT → empty string
# ------------------------------------------------------------
find_best_sink() {
  local dump
  dump="$(pw-dump 2>/dev/null)" || dump=""

  if [[ -n "$dump" ]]; then
    # 1. JBL by MAC embedded in node name
    local jbl_id
    jbl_id="$(echo "$dump" | jq -r --arg mac "bluez_output.${JBL_MAC}" \
      '[.[] | select(.type == "PipeWire:Interface:Node") | select(.info.props["node.name"] // "" | startswith($mac))] | first | .id // empty')"
    [[ -n "$jbl_id" ]] && echo "$jbl_id" && return

    # 2. Any other Bluetooth sink
    local bt_id
    bt_id="$(echo "$dump" | jq -r \
      '[.[] | select(.type == "PipeWire:Interface:Node") | select(.info.props["node.name"] // "" | startswith("bluez_output"))] | first | .id // empty')"
    [[ -n "$bt_id" ]] && echo "$bt_id" && return
  fi

  # 3. Fall back to system default sink
  echo "@DEFAULT_AUDIO_SINK@"
}

# ------------------------------------------------------------
# Handle control commands: volume up|down|toggle
# ------------------------------------------------------------
CMD="${1:-}"
if [[ -n "$CMD" ]]; then
  case "$CMD" in
    up|right) wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+ ;;
    down|left) wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%- ;;
    toggle)   wpctl set-mute   @DEFAULT_AUDIO_SINK@ toggle ;;
  esac
  pkill -RTMIN+1 waybar
  exit 0
fi

# shellcheck source=/dev/null
source "$HOME/.config/waybar/palette.sh"

SINK="$(find_best_sink)"

# ------------------------------------------------------------
# 1️⃣ Read volume and mute state from best available sink
# ------------------------------------------------------------
if [[ -z "$SINK" ]]; then
  vol=0
  mute="true"
else
  raw="$(wpctl get-volume "$SINK" 2>/dev/null || echo "Volume: 0")"
  vol_float="$(echo "$raw" | awk '{print $2}')"
  vol="$(awk -v v="${vol_float:-0}" 'BEGIN { printf "%d", v * 100 }')"
  [[ "$raw" == *"[MUTED]"* ]] && mute="true" || mute="false"
fi

[[ "$vol" =~ ^[0-9]+$ ]] || vol=0
(( vol > 100 )) && vol=100

VALUE="${vol}%"
GLYPH="󰕾"

# ------------------------------------------------------------
# 2️⃣ Determine the *semantic* bucket (low/medium/high/full/muted)
# ------------------------------------------------------------
if [[ "$mute" == "true" || "$vol" -eq 0 ]]; then
  CLASS="muted"
  bucket="mute"
else
  if   (( vol < 30 )); then bucket="low"
  elif (( vol < 70 )); then bucket="medium"
  elif (( vol < 100 )); then bucket="high"
  else bucket="full"
  fi
  CLASS="$bucket"
fi

# ------------------------------------------------------------
# 3️⃣ Determine the *gradient* bucket (every 5 %)
# ------------------------------------------------------------
grad=$(( (vol / 5) * 5 ))
GRADIENT="vol-${grad}"          # e.g. "vol-35"

# ------------------------------------------------------------
# 4️⃣ Build the text that Waybar will display
# ------------------------------------------------------------
TEXT="${GLYPH} ${VALUE}"

# ------------------------------------------------------------
# 5️⃣ Snark system (optional flavour)
# ------------------------------------------------------------
SNARK_FILE="$HOME/.config/waybar/snark.json"
snark="Volume exists."

if [[ -f "$SNARK_FILE" ]] && command -v jq >/dev/null 2>&1; then
  snark="$(jq -r ".volume.${bucket}[]?" "$SNARK_FILE" | shuf -n1 || true)"
  [[ -n "${snark:-}" && "$snark" != "null" ]] || snark="Volume exists."
fi

case "$bucket" in
  mute)   VOL_COLOR="$MUTED"        ;;
  low)    VOL_COLOR="$FOAM"         ;;
  medium) VOL_COLOR="$TEXT_PRIMARY" ;;
  high)   VOL_COLOR="$GOLD"         ;;
  full)   VOL_COLOR="$LOVE"         ;;
  *)      VOL_COLOR="$TEXT_PRIMARY" ;;
esac

TOOLTIP="$(printf "<span foreground='${MUTED}'>Volume:</span> <span foreground='${VOL_COLOR}'>%s</span>\n<span foreground='${MUTED}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$VALUE" "$snark")"

# ------------------------------------------------------------
# 6️⃣ Emit JSON – pass class as an array so Waybar applies BOTH CSS classes
# ------------------------------------------------------------
jq -nc \
  --arg text "$TEXT" \
  --arg tooltip "$TOOLTIP" \
  --arg class1 "$CLASS" \
  --arg class2 "$GRADIENT" \
  '{text:$text, tooltip:$tooltip, class:[$class1,$class2]}'
