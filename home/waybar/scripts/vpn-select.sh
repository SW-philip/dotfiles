#!/usr/bin/env bash
set -euo pipefail

WGDIR="$HOME/.config/wireguard"
ACTIVE="$WGDIR/protonvpn.conf"
SERVICE="wg-quick-protonvpn.service"
SYSTEMCTL="/run/current-system/sw/bin/systemctl"
SUDO="/run/wrappers/bin/sudo"

# Collect available server configs (exclude the active-slot file itself)
configs=()
while IFS= read -r -d '' f; do
  [[ "$(basename "$f")" == "protonvpn.conf" ]] && continue
  configs+=("$f")
done < <(find "$WGDIR" -maxdepth 1 -name "*.conf" -print0 2>/dev/null | sort -z)

vpn_active=$($SYSTEMCTL is-active --quiet "$SERVICE" 2>/dev/null && echo yes || echo no)

current_target=""
[[ -L "$ACTIVE" ]] && current_target=$(readlink -f "$ACTIVE" 2>/dev/null || true)

choices=()
for f in "${configs[@]}"; do
  name=$(basename "$f" .conf)
  real=$(readlink -f "$f" 2>/dev/null || echo "$f")
  if [[ "$real" == "$current_target" && "$vpn_active" == "yes" ]]; then
    choices+=("󰖂  $name  [connected]")
  else
    choices+=("    $name")
  fi
done

[[ "$vpn_active" == "yes" ]] && choices+=("󰖪  Disconnect")

if [[ ${#choices[@]} -eq 0 ]]; then
  notify-send "VPN" "No configs found in $WGDIR"
  exit 0
fi

choice=$(printf '%s\n' "${choices[@]}" | fuzzel --dmenu --prompt "VPN › " --width 32) || exit 0

if [[ "$choice" == "󰖪  Disconnect" ]]; then
  $SUDO -n $SYSTEMCTL stop "$SERVICE" && \
    notify-send "VPN" "Disconnected" -i network-vpn-off || \
    notify-send "VPN" "Disconnect failed" -i network-vpn-error
  exit 0
fi

# Strip icon prefix and [connected] suffix to recover the filename stem
server=$(echo "$choice" | sed 's/^[^a-zA-Z0-9]*//' | sed 's/  \[connected\]$//')
selected="$WGDIR/${server}.conf"

if [[ ! -f "$selected" ]]; then
  notify-send "VPN" "Config not found: $server"
  exit 1
fi

# Stop any running tunnel
[[ "$vpn_active" == "yes" ]] && $SUDO -n $SYSTEMCTL stop "$SERVICE" || true

# Swap the active slot to the chosen server
ln -sf "$selected" "$ACTIVE"

$SUDO -n $SYSTEMCTL start "$SERVICE" && \
  notify-send "VPN" "Connected: $server" -i network-vpn-symbolic || \
  notify-send "VPN" "Failed to connect: $server" -i network-vpn-error
