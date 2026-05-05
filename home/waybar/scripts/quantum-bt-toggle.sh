#!/usr/bin/env bash

ADAPTER="/org/bluez/hci0"

# bluetoothctl subcommand mode doesn't wait for DBus in bluez 5.86+; use busctl instead
bt_powered=$(busctl get-property org.bluez "$ADAPTER" org.bluez.Adapter1 Powered 2>/dev/null | awk '{print $2}')

if [[ "$bt_powered" == "true" ]]; then
    busctl set-property org.bluez "$ADAPTER" org.bluez.Adapter1 Powered b false
    notify-send -i bluetooth "Bluetooth" "Powered Off"
else
    busctl set-property org.bluez "$ADAPTER" org.bluez.Adapter1 Powered b true
    busctl set-property org.bluez "$ADAPTER" org.bluez.Adapter1 Discoverable b true
    notify-send -i bluetooth "Bluetooth" "Powered On"
fi
