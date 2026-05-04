#!/usr/bin/env bash
set -euo pipefail

# 1. Force Wayland and bypass X11 legacy behavior
export BEMENU_BACKEND=wayland

# 2. Prevent 'unbound variable' error
CACHE="$HOME/.cache/quantum_bt"
mkdir -p "$CACHE"
FAVES="$CACHE/favorites"
touch "$FAVES"

# 3. Source your Rosé Pine palette[cite: 1]
PALETTE="$HOME/.config/waybar/palette.sh"
[[ -f "$PALETTE" ]] && source "$PALETTE"

# 4. Use absolute width (600px) and center flag
# Note: Double quotes are used so the shell expands your theme variables
launcher="bemenu --list 12 --center --fixed-height --width 600 \
  --nb ${BASE:-#232136} --nf ${TEXT:-#e0def4} \
  --hb ${SURFACE:-#2a273f} --hf ${PINE:-#3e8fb0} \
  --fb ${BASE:-#232136} --ff ${FOAM:-#9ccfd8} \
  --tb ${BASE:-#232136} --tf ${LOVE:-#eb6f92} \
  --ab ${BASE:-#232136} --af ${SUBTLE:-#908caa} \
  --fn 'JetBrainsMono Nerd Font 12' \
  --prompt '🔊 choose bond:'"

ADAPTER="/org/bluez/hci0"

# 4. Check Power
if ! busctl get-property org.bluez "$ADAPTER" org.bluez.Adapter1 Powered | grep -q "true"; then
    notify-send "Bluetooth" "Please turn Bluetooth on first."
    exit 1
fi

# 5. Device Scanning and mapfile Logic[cite: 2, 5]
bluetoothctl scan on >/dev/null 2>&1 &
SCAN_PID=$!
sleep 2
kill $SCAN_PID 2>/dev/null || true

mapfile -t devices < <(printf 'devices\nquit\n' | bluetoothctl | \
    sed 's/\x1b\[[0-9;]*m//g;s/\r//g' | awk '/^Device/{$1=""; print substr($0,2)}')

if [[ ${#devices[@]} -eq 0 ]]; then
    notify-send "Bluetooth" "No paired devices found."
    exit 1
fi

choices=()
for dev in "${devices[@]}"; do
    mac=$(echo "$dev" | awk '{print $1}')
    info=$(printf "info %s\nquit\n" "$mac" | bluetoothctl | sed 's/\x1b\[[0-9;]*m//g;s/\r//g')
    alias=$(echo "$info" | awk -F': ' '/Alias/ {print $2}' | xargs)

    favmark=""; grep -qx "$mac" "$FAVES" && favmark="⭐ "

    status="⚪"; echo "$info" | grep -q "Connected: yes" && status="🟢"
    choices+=("$status $favmark $alias ($mac)")
done

# 6. Execute launcher and handle selection[cite: 5]
choice=$(printf '%s\n' "${choices[@]}" | $launcher)
[[ -z "$choice" ]] && exit 0

mac=$(echo "$choice" | grep -oE '([0-9A-F]{2}:){5}[0-9A-F]{2}')
[[ -z "$mac" ]] && exit 0

# 7. Action Menu (Uses the same dynamic launcher flags)[cite: 5]
action=$(printf "connect/disconnect\ntoggle favorite" | $launcher --prompt "Action:")
[[ -z "$action" ]] && exit 0

if [[ "$action" == "toggle favorite" ]]; then
    if grep -qx "$mac" "$FAVES"; then
        sed -i "/$mac/d" "$FAVES"
        notify-send "Bluetooth" "Removed favorite"
    else
        echo "$mac" >> "$FAVES"
        notify-send "Bluetooth" "Added favorite"
    fi
    exit 0
fi

# 8. Connection and Audio Routing[cite: 2, 5]
if printf "info %s\nquit\n" "$mac" | bluetoothctl | grep -q "Connected: yes"; then
    printf "disconnect %s\nquit\n" "$mac" | bluetoothctl >/dev/null
    notify-send "Bluetooth" "Disconnected"
else
    notify-send "Bluetooth" "Connecting..."
    if printf "connect %s\nquit\n" "$mac" | bluetoothctl | grep -q "Connection successful"; then
        notify-send "Bluetooth" "Connected"

        # Audio routing logic for PipeWire
        mac_under="${mac//:/_}"
        sleep 2
        sink_id=$(pw-dump | jq -r --arg name "bluez_output.${mac_under}" \
          '.[] | select(.info.props["node.name"] | startswith($name)?) | .id' | head -n1)
        [[ -n "$sink_id" ]] && wpctl set-default "$sink_id"
    else
        notify-send "Bluetooth" "Connection failed"
    fi
fi
