#!/usr/bin/env bash
set -euo pipefail

SNARK_FILE="$HOME/.config/waybar/snark.json"
# shellcheck source=/dev/null
source "$HOME/.config/waybar/palette.sh"

snark_for() {
  local bucket="$1"
  local fallback="$2"
  if [[ -f "$SNARK_FILE" ]] && command -v jq >/dev/null; then
    local s
    s=$(jq -r ".network.${bucket}[]?" "$SNARK_FILE" 2>/dev/null | shuf -n1 || true)
    [[ -n "$s" && "$s" != "null" ]] && { echo "$s"; return; }
  fi
  echo "$fallback"
}

# Nerd Font glyph arsenal
ICON_WIFI="󰖩"
ICON_WIRED="󰈀"
ICON_OFFLINE="󰖪"
ICON_VPN="󰖂"
ICON_AIRPLANE="󰀝"

class="offline"
text="$ICON_OFFLINE"
tooltip=$(printf "<span foreground='${SUBTLE}'>Offline</span>\n<span foreground='${SUBTLE}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$(snark_for offline 'communing with nature.')")

# Airplane mode check (if rfkill exists)
if command -v rfkill >/dev/null; then
  if rfkill list all | grep -qi "Soft blocked: yes"; then
    jq -nc --arg text "$ICON_AIRPLANE" \
           --arg tooltip "$(printf "<span foreground='${GOLD}'>Airplane mode</span>\n<span foreground='${SUBTLE}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$(snark_for airplane 'Airplane mode engaged.')")" \
           --arg class "airplane" \
           '{text:$text, tooltip:$tooltip, class:$class}'
    exit 0
  fi
fi

# Measure network speed (bytes/s over 1s sample)
get_speed() {
  local iface="$1"
  local rx1 tx1 rx2 tx2
  rx1=$(cat /sys/class/net/"$iface"/statistics/rx_bytes 2>/dev/null || echo 0)
  tx1=$(cat /sys/class/net/"$iface"/statistics/tx_bytes 2>/dev/null || echo 0)
  sleep 1
  rx2=$(cat /sys/class/net/"$iface"/statistics/rx_bytes 2>/dev/null || echo 0)
  tx2=$(cat /sys/class/net/"$iface"/statistics/tx_bytes 2>/dev/null || echo 0)
  local rx_bps=$(( rx2 - rx1 ))
  local tx_bps=$(( tx2 - tx1 ))
  # Format as human-readable
  format_speed() {
    local b="$1"
    if (( b >= 1048576 )); then
      awk "BEGIN{printf \"%.1f MB/s\", $b/1048576}"
    elif (( b >= 1024 )); then
      awk "BEGIN{printf \"%.1f KB/s\", $b/1024}"
    else
      echo "${b} B/s"
    fi
  }
  echo "↓ $(format_speed $rx_bps)  ↑ $(format_speed $tx_bps)"
}

# VPN status
if systemctl is-active --quiet wg-quick-protonvpn.service 2>/dev/null; then
  vpn_status="<span foreground='${IRIS}'>VPN on</span>"
else
  vpn_status="<span foreground='${SUBTLE}'>VPN off</span>"
fi

# Detect active network interface dynamically
active_iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')

if [[ -z "$active_iface" ]]; then
  mode="offline"
  iface_ip=""
  iface_speed=""
else
  case "$active_iface" in
    wl*) mode="wifi" ;;
    en*|eth*) mode="wired" ;;
    tun*|wg*|vpn*|*vpn*) mode="vpn" ;;
    *) mode="wired" ;;
  esac
  iface_ip=$(ip addr show "$active_iface" 2>/dev/null \
    | awk '/inet /{print $2; exit}')
  iface_speed=$(get_speed "$active_iface")
fi

case "$mode" in
  wifi)
    if command -v nmcli >/dev/null; then
      signal="$(nmcli -t -f active,signal dev wifi 2>/dev/null \
        | awk -F: '$1=="yes"{print $2}' | head -n1)"
    else
      signal=""
    fi

    signal="${signal:-0}"

    if   (( signal < 25 )); then text="▂";    class="wifi low";  bucket="low"
    elif (( signal < 50 )); then text="▂▄";   class="wifi mid";  bucket="mid"
    elif (( signal < 75 )); then text="▂▄▆";  class="wifi high"; bucket="high"
    else                        text="▂▄▆█"; class="wifi full"; bucket="full"
    fi

    text="$ICON_WIFI $text"
    tooltip=$(printf "<span foreground='${SUBTLE}'>Wi-Fi:</span> <span foreground='${FOAM}'>%s%%</span> signal\n<span foreground='${SUBTLE}'>IP:</span> <span foreground='${TEXT}'>%s</span>\n%s\n<span foreground='${SUBTLE}'>%s</span>\n<span foreground='${SUBTLE}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" \
      "$signal" "${iface_ip:-no IP}" "$vpn_status" "$iface_speed" \
      "$(snark_for "$bucket" 'Signal present.')")
    ;;

  wired)
    text="$ICON_WIRED"
    class="wired"
    tooltip=$(printf "<span foreground='${TEXT}'>Wired</span>\n<span foreground='${SUBTLE}'>IP:</span> <span foreground='${TEXT}'>%s</span>\n%s\n<span foreground='${SUBTLE}'>%s</span>\n<span foreground='${SUBTLE}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" \
      "${iface_ip:-no IP}" "$vpn_status" "$iface_speed" \
      "$(snark_for wired 'unbothered, unstoppable.')")
    ;;

  vpn)
    text="$ICON_VPN"
    class="vpn"
    tooltip=$(printf "<span foreground='${IRIS}'>VPN active</span>\n<span foreground='${SUBTLE}'>IP:</span> <span foreground='${TEXT}'>%s</span>\n<span foreground='${SUBTLE}'>%s</span>\n<span foreground='${SUBTLE}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" \
      "${iface_ip:-no IP}" "$iface_speed" \
      "$(snark_for vpn 'anonymous-ish hero mode.')")
    ;;

  *)
    text="$ICON_OFFLINE"
    class="offline"
    tooltip=$(printf "<span foreground='${SUBTLE}'>Offline</span>\n<span foreground='${SUBTLE}'>────────────────────</span>\n<span foreground='${IRIS}'>%s</span>" "$(snark_for offline 'touching grass.')")
    ;;
esac

jq -nc \
  --arg text "$text" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  '{text:$text, tooltip:$tooltip, class:$class}'
