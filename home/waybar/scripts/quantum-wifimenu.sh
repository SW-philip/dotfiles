#!/usr/bin/env bash
set -euo pipefail

CACHE="$HOME/.cache/quantum_wifi"
mkdir -p "$CACHE"
FAVES="$CACHE/favorites"
touch "$FAVES"

launcher="wofi --dmenu -p '📡 choose signal:'"
WIFI_LOG=$(mktemp)
trap 'rm -f "$WIFI_LOG"' EXIT
active_ssid="$(nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2}')"

bars() {
  local s=$1
  if   (( s < 25 )); then echo "▂"
  elif (( s < 50 )); then echo "▂▄"
  elif (( s < 75 )); then echo "▂▄▆"
  else                    echo "▂▄▆█"
  fi
}

security_label() {
  case "$1" in
    *WPA3*) echo "WPA3" ;;
    *WPA2*) echo "WPA2" ;;
    *WEP*)  echo "WEP" ;;
    "")     echo "OPEN" ;;
    *)      echo "$1" ;;
  esac
}

mapfile -t nets < <(
  nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list --rescan yes \
  | grep -v '^$' \
  | sort -t: -k2 -nr
)

choices=()

if [[ -n "$active_ssid" ]]; then
  choices+=("🔗 Connected: $active_ssid")
else
  choices+=("❌ Not connected")
fi

choices+=("🔁 Rescan networks")
choices+=("────────────────────────────")

for net in "${nets[@]}"; do
  ssid=$(echo "$net" | cut -d: -f1)
  signal=$(echo "$net" | cut -d: -f2)
  sec=$(echo "$net" | cut -d: -f3)

  [[ -z "$ssid" ]] && continue

  favmark=""
  grep -qxF "$ssid" "$FAVES" && favmark="⭐ "

  bar="$(bars "$signal")"
  seclabel="$(security_label "$sec")"

  safe_ssid=$(printf '%s' "$ssid" | sed 's/[<>&]/_/g')

  if [[ "$ssid" == "$active_ssid" ]]; then
    choices+=("📶 $favmark$safe_ssid $bar [$signal%] ($seclabel)")
  else
    choices+=("📡 $favmark$safe_ssid $bar [$signal%] ($seclabel)")
  fi
done

choice=$(printf '%s\n' "${choices[@]}" | bash -c "$launcher")
[[ -z "$choice" ]] && exit 0

if [[ "$choice" == *"Rescan networks"* ]]; then
  notify-send "Wi-Fi" "🔁 rescanning..."
  exec "$0"
fi

ssid=$(echo "$choice" | sed -E 's/.*(📶|📡) //; s/ ▂.*//')

[[ -z "$ssid" ]] && exit 0

if [[ "$ssid" == "$active_ssid" ]]; then
  nmcli con down "$ssid" || true
  notify-send "Wi-Fi" "📴 disconnected from $ssid"
  exit 0
fi

notify-send "Wi-Fi" "connecting to $ssid..."

if nmcli -w 10 dev wifi connect "$ssid" >"$WIFI_LOG" 2>&1; then
  notify-send "Wi-Fi" "✅ connected to $ssid"
  exit 0
fi

if grep -qi "Secrets were required" "$WIFI_LOG"; then
  pass=$(fuzzel --dmenu --prompt "🔑 password for $ssid:" --width 480)

  if nmcli dev wifi connect "$ssid" password "$pass"; then
    notify-send "Wi-Fi" "✅ connected to $ssid"
  else
    notify-send "Wi-Fi" "❌ authentication failed"
  fi
else
  notify-send "Wi-Fi" "❌ failed to connect to $ssid"
fi
