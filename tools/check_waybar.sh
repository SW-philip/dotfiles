#!/usr/bin/env bash

# Define the directory to scan
TARGET_DIR="$HOME/nixos/home/waybar"

echo "--- Checking for hardcoded 'mainBar' references ---"
# -r: recursive, -n: show line number, -w: match whole word
grep -rnw "$TARGET_DIR" -e "mainBar"

if [ $? -eq 0 ]; then
    echo -e "\n❌ FOUND ERRORS: The files above are still targeting 'mainBar'."
    echo "They need to use the dynamic \${bar} variable instead."
else
    echo -e "\n✅ CLEAN: No 'mainBar' references found."
fi

echo -e "\n--- Checking for missing options/config blocks ---"
for file in "$TARGET_DIR"/*.nix; do
    if [[ $(basename "$file") != "default.nix" ]]; then
        if ! grep -q "options.waybar" "$file"; then
            echo "⚠️  WARNING: $(basename "$file") is missing an 'options' block."
        fi
    fi
done
