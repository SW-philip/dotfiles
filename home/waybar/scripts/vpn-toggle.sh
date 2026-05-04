#!/usr/bin/env bash

SUDO=/run/wrappers/bin/sudo

if systemctl is-active --quiet wg-quick-protonvpn.service; then
    $SUDO systemctl stop wg-quick-protonvpn.service && \
        notify-send "VPN" "ProtonVPN Disconnected" -i network-vpn-off || \
        notify-send "VPN" "Disconnect failed" -i network-vpn-off
else
    $SUDO systemctl start wg-quick-protonvpn.service && \
        notify-send "VPN" "ProtonVPN Connected" -i network-vpn-symbolic || \
        notify-send "VPN" "Connect failed" -i network-vpn-off
fi
