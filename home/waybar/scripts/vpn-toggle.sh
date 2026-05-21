#!/usr/bin/env bash

SYSTEMCTL="/run/current-system/sw/bin/systemctl"
SUDO="/run/wrappers/bin/sudo"

declare -A VPN_SERVICES=(
  ["New York"]="protonvpn-ny"
  ["Brisbane, AU"]="protonvpn-au"
  ["Canada"]="protonvpn-ca"
)
VPN_ORDER=("New York" "Brisbane, AU" "Canada")

# Detect active ProtonVPN tunnel
active_vpn_svc=""
active_vpn_label=""
for label in "${VPN_ORDER[@]}"; do
  svc="wg-quick-${VPN_SERVICES[$label]}.service"
  if $SYSTEMCTL is-active --quiet "$svc" 2>/dev/null; then
    active_vpn_svc="$svc"
    active_vpn_label="$label"
    break
  fi
done

# Detect Tailscale state
tailscale_on=false
$SYSTEMCTL is-active --quiet tailscaled.service 2>/dev/null && tailscale_on=true

# Build menu entries, marking the active one
entries=()
for label in "${VPN_ORDER[@]}"; do
  if [ "$active_vpn_label" = "$label" ]; then
    entries+=("󰖂  $label  [on]")
  else
    entries+=("    $label")
  fi
done

if $tailscale_on; then
  entries+=("󰒄  Tailscale  [on]")
else
  entries+=("    Tailscale")
fi
entries+=("󰖪  Disconnect")

choice=$(printf '%s\n' "${entries[@]}" \
  | fuzzel --dmenu --prompt "Network › " --width 300 --lines 5) || exit 0
[ -z "$choice" ] && exit 0

if [[ "$choice" == *"Disconnect"* ]]; then
  [ -n "$active_vpn_svc" ] && $SUDO -n $SYSTEMCTL stop "$active_vpn_svc" 2>/dev/null
  $tailscale_on && $SUDO -n $SYSTEMCTL stop tailscaled.service 2>/dev/null
  notify-send "Network" "Disconnected" -i network-vpn-off
  exit 0
fi

if [[ "$choice" == *"Tailscale"* ]]; then
  if $tailscale_on; then
    $SUDO -n $SYSTEMCTL stop tailscaled.service && \
      notify-send "Tailscale" "Disconnected" -i network-vpn-off || \
      notify-send "Tailscale" "Disconnect failed" -i network-error
  else
    [ -n "$active_vpn_svc" ] && $SUDO -n $SYSTEMCTL stop "$active_vpn_svc" 2>/dev/null
    $SUDO -n $SYSTEMCTL start tailscaled.service && \
      notify-send "Tailscale" "Connected" -i network-vpn-symbolic || \
      notify-send "Tailscale" "Connect failed" -i network-error
  fi
  exit 0
fi

# ProtonVPN selection — strip icon prefix and [on] suffix to recover the label
selected_label=$(echo "$choice" | sed 's/^[^A-Za-z]*//' | sed 's/  \[on\]$//')
target="${VPN_SERVICES[$selected_label]:-}"
[ -z "$target" ] && exit 1

$tailscale_on && $SUDO -n $SYSTEMCTL stop tailscaled.service 2>/dev/null
[ -n "$active_vpn_svc" ] && $SUDO -n $SYSTEMCTL stop "$active_vpn_svc" 2>/dev/null

$SUDO -n $SYSTEMCTL start "wg-quick-${target}.service" && \
  notify-send "VPN" "Connected — $selected_label" -i network-vpn-symbolic || \
  notify-send "VPN" "Connect failed" -i network-error
