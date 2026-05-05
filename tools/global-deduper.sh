#!/usr/bin/env bash

THEME_ROOT="$HOME/nixos/themes"
TEMP_ALL_COLORS="/tmp/all_hex_codes.txt"

# Extract every hex code from every active nix file
find "$THEME_ROOT" -name "*.nix" -not -path "*/themesbk/*" -exec grep -oP '#[0-9a-fA-F]{6}' {} + | tr '[:upper:]' '[:lower:]' > "$TEMP_ALL_COLORS"

echo "--- 📊 System-Wide Color Deduplication ---"
echo "Total Hex References: $(wc -l < "$TEMP_ALL_COLORS")"
echo "Total Unique Colors:  $(sort -u "$TEMP_ALL_COLORS" | wc -l)"
echo "------------------------------------------"

# List the top 10 most used colors (The "Over-Synced" culprits)
echo "Most common colors (likely synced defaults):"
sort "$TEMP_ALL_COLORS" | uniq -c | sort -nr | head -n 10

rm "$TEMP_ALL_COLORS"
