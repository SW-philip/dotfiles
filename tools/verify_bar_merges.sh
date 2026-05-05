#!/usr/bin/env bash

CONFIG="$HOME/.config/waybar/config"

if [ ! -f "$CONFIG" ]; then
    echo "❌ Waybar config not found at $CONFIG. Run 'nrs' first."
    exit 1
fi

echo "--- 📊 Waybar JSON Structure Audit ---"

# 1. Check the top-level keys
KEYS=$(jq -r 'keys | join(", ")' "$CONFIG")
echo -e "Top-level bars found: \033[1;34m$KEYS\033[0m"

# 2. Check for the "Poison" mainBar or Anonymous Lists
if [[ "$KEYS" == *"mainBar"* ]]; then
    echo -e "⚠️  WARNING: 'mainBar' detected. One of your modules is still hardcoded to mainBar."
fi

if [[ "$KEYS" =~ [0-9] ]]; then
    echo -e "⚠️  WARNING: Numeric keys (0, 1) detected. Nix is rendering a list instead of an object."
fi

echo "--------------------------------------"

# 3. Check what's actually INSIDE your Surface bars
for bar in "surfaceTopBar" "surfaceBottomBar"; do
    if [[ "$KEYS" == *"$bar"* ]]; then
        echo -e "✅ \033[1;32m$bar\033[0m contains these module configs:"
        jq -r ".\"$bar\" | keys | .[]" "$CONFIG" | grep "custom/" | sed 's/^/  - /'
        
        # Check if modules defined in layout actually have config
        echo "   Checking layout vs config..."
        LAYOUT=$(jq -r ".\"$bar\".\"modules-left\" + .\"$bar\".\"modules-center\" + .\"$bar\".\"modules-right\" | .[]" "$CONFIG" | grep "custom/")
        for mod in $LAYOUT; do
            if ! jq -e ".\"$bar\".\"$mod\"" "$CONFIG" > /dev/null; then
                echo -e "   ❌ \033[0;31mBROKEN:\033[0m $mod is in the layout but has NO config in this bar."
            fi
        done
    else
        echo -e "❌ \033[0;31m$bar\033[0m is missing from the final JSON!"
    fi
    echo ""
done
