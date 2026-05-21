#!/usr/bin/env bash

# True Nerd Font 3.x Bluetooth glyphs
ICON_OFF="󰂲"
ICON_ON="󰂯"
ICON_CONNECTED="󰂱"

# Rosé Pine Moon — matches palette.nix
C_MUTED="#6e6a86"
C_SUBTLE="#908caa"
C_ICON="#c4c0d8"
C_TEXT="#e0def4"
C_FOAM="#9ccfd8"
C_IRIS="#c4a7e7"

SNARK_FILE="$HOME/.config/waybar/snark.json"
ADAPTER="/org/bluez/hci0"

snark_for() {
    local bucket="$1" fallback="${2:-}"
    if [[ -f "$SNARK_FILE" ]] && command -v jq >/dev/null; then
        local s
        s=$(jq -r ".bluetooth.${bucket}[]?" "$SNARK_FILE" 2>/dev/null | shuf -n1 || true)
        [[ -n "$s" && "$s" != "null" ]] && echo "$s" && return
    fi
    echo "$fallback"
}

# bluetoothctl subcommand mode doesn't wait for DBus in bluez 5.86+; use busctl instead
bt_powered=$(busctl get-property org.bluez "$ADAPTER" org.bluez.Adapter1 Powered 2>/dev/null | awk '{print $2}')

if [[ "$bt_powered" != "true" ]]; then
    jq -cn \
        --arg text "<span foreground='$C_SUBTLE'>$ICON_OFF</span>" \
        --arg tooltip "Bluetooth <span foreground='$C_SUBTLE'>off</span>
<span foreground='$C_SUBTLE'>────────────────────</span>
<span foreground='$C_IRIS'>$(snark_for off 'Radio silence.')</span>" \
        --arg class "off" \
        '{text: $text, tooltip: $tooltip, class: $class}'
    exit 0
fi

# Interactive pipe mode required for device enumeration in bluez 5.86+
connected_mac=$(printf 'devices Connected\nquit\n' | bluetoothctl 2>/dev/null | \
    sed 's/\x1b\[[0-9;]*m//g;s/\r//g' | awk '/^Device/{print $2; exit}')

sink_line=$(wpctl status | grep -E "bluez_output" | head -n1)

if [[ -n "$connected_mac" ]]; then
    info=$(printf "info %s\nquit\n" "$connected_mac" | bluetoothctl 2>/dev/null | \
        sed 's/\x1b\[[0-9;]*m//g;s/\r//g')
    name=$(echo "$info" | awk -F': ' '/Alias/ {print $2}')

    text="<span foreground='$C_FOAM'>$ICON_CONNECTED</span>  <span foreground='$C_TEXT' size='small'>$name</span>"

    _snark=$(snark_for on 'Wirelessly entangled.')
    if [[ -n "$sink_line" ]]; then
        tooltip="<b>Connected</b>"$'\n'"<span foreground='$C_ICON'>$name</span>"$'\n'"<span foreground='$C_FOAM' size='small'>● audio sink active</span>"
    else
        tooltip="<b>Connected</b>"$'\n'"<span foreground='$C_ICON'>$name</span>"
    fi
    tooltip+=$'\n'"<span foreground='$C_SUBTLE'>────────────────────</span>"$'\n'"<span foreground='$C_IRIS'>$_snark</span>"

    jq -cn \
        --arg text "$text" \
        --arg tooltip "$tooltip" \
        --arg class "on" \
        '{text: $text, tooltip: $tooltip, class: $class}'
    exit 0
fi

# Powered but not connected fallback
jq -cn \
    --arg text "<span foreground='$C_ICON'>$ICON_ON</span>" \
    --arg tooltip "Bluetooth <span foreground='$C_SUBTLE'>on</span> · no device
<span foreground='$C_SUBTLE'>────────────────────</span>
<span foreground='$C_IRIS'>$(snark_for idle 'Scanning...')</span>" \
    --arg class "idle" \
    '{text: $text, tooltip: $tooltip, class: $class}'
