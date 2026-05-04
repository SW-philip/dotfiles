#!/usr/bin/env bash

THEME_ROOT="$HOME/nixos/themes"
MAIN_PURPLE="#191724"

echo "--- 🕵️ Searching for 'Main' Palette Bleed ---"
echo "Files containing the default Rosé Pine Main base color:"
echo "-------------------------------------------------------"

find "$THEME_ROOT" -name "*.nix" -not -path "*/themesbk/*" | while read -r file; do
    # Count how many times the Main purple appears
    count=$(grep -ic "$MAIN_PURPLE" "$file")

    if [ "$count" -gt 0 ]; then
        rel_path=$(echo "$file" | sed "s|$THEME_ROOT/||")
        # If the count is high, it means the theme hasn't been properly unique-ified
        if [ "$count" -gt 5 ]; then
            echo "🚨 $rel_path: $count occurrences (Likely a generic clone)"
        else
            echo "🟡 $rel_path: $count occurrences (Minor overlap)"
        fi
    fi
done
