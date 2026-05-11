#!/usr/bin/env bash

SYSTEMCTL="/run/current-system/sw/bin/systemctl"
SUDO="/run/wrappers/bin/sudo"

declare -A SERVICES=(
  ["New York"]="protonvpn-ny"
  ["Brisbane, AU"]="protonvpn-au"
  ["Canada"]="protonvpn-ca"
)

active_service=""
active_label=""
for label in "New York" "Brisbane, AU" "Canada"; do
  svc="wg-quick-${SERVICES[$label]}.service"
  if $SYSTEMCTL is-active --quiet "$svc" 2>/dev/null; then
    active_service="$svc"
    active_label="$label"
    break
  fi
done

choice=$(printf 'New York\nBrisbane, AU\nCanada\nDisconnect' \
  | fuzzel --dmenu --prompt "VPN › " --width 300 --lines 4)
[ -z "$choice" ] && exit 0

[ -n "$active_service" ] && $SUDO -n $SYSTEMCTL stop "$active_service" 2>/dev/null

if [ "$choice" = "Disconnect" ]; then
  [ -n "$active_label" ] && notify-send "VPN" "Disconnected" -i network-vpn-off
  exit 0
fi

target="${SERVICES[$choice]}"
$SUDO -n $SYSTEMCTL start "wg-quick-${target}.service" && \
  notify-send "VPN" "Connected — $choice" -i network-vpn-symbolic || \
  notify-send "VPN" "Connect failed" -i network-vpn-error
