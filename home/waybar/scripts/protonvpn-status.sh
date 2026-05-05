#!/usr/bin/env bash
# Waybar ProtonVPN WireGuard status indicator

PALETTE="$HOME/.config/waybar/palette.sh"
# shellcheck source=/dev/null
source "$PALETTE" 2>/dev/null || true

PINE="${PINE:-#31748f}"
MUTED="${MUTED:-#6e6a86}"
LOVE="${LOVE:-#eb6f92}"

ICON_ON="󰖂"
ICON_OFF="󰦞"

if systemctl is-active --quiet wg-quick-protonvpn.service 2>/dev/null; then
    printf '{"text": "%s", "tooltip": "<span foreground='"'"'%s'"'"'>ProtonVPN Connected</span>", "class": "vpn-on"}\n' \
        "$ICON_ON" "$PINE"
else
    printf '{"text": "%s", "tooltip": "<span foreground='"'"'%s'"'"'>ProtonVPN Off</span>\\n<span foreground='"'"'%s'"'"'>Click to connect</span>", "class": "vpn-off"}\n' \
        "$ICON_OFF" "$MUTED" "$MUTED"
fi
