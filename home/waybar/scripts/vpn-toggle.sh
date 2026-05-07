#!/usr/bin/env bash

# Match the path used in your NixOS sudo rules
SYSTEMCTL="/run/current-system/sw/bin/systemctl"
SUDO="/run/wrappers/bin/sudo"
SERVICE="wg-quick-protonvpn.service"

if $SYSTEMCTL is-active --quiet "$SERVICE"; then
    # The -n flag ensures it never hangs Waybar
    $SUDO -n $SYSTEMCTL stop "$SERVICE" && \
        notify-send "VPN" "ProtonVPN Disconnected" -i network-vpn-off || \
        notify-send "VPN" "Disconnect failed" -i network-vpn-error
else
    $SUDO -n $SYSTEMCTL start "$SERVICE" && \
        notify-send "VPN" "ProtonVPN Connected" -i network-vpn-symbolic || \
        notify-send "VPN" "Connect failed" -i network-vpn-error
fi
