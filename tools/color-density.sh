#!/usr/bin/env bash

THEME_ROOT="$HOME/nixos/themes"

echo "--- 🎨 Unique Color Density Report ---"
echo "Format: [Unique Colors Count] | [File Path]"
echo "------------------------------------------------"

find "$THEME_ROOT" -name "*.nix" -not -path "*/themesbk/*" | while read -r file; do
    # 1. Extract all hex codes
    # 2. Convert to lowercase for accurate deduping
    # 3. Count unique occurrences
    unique_count=$(grep -oP '#[0-9a-fA-F]{6}' "$file" | tr '[:upper:]' '[:lower:]' | sort -u | wc -l)

    rel_path=$(echo "$file" | sed "s|$THEME_ROOT/||")

    # Visual cues for density
    if [ "$unique_count" -lt 10 ]; then
        status="🚨 FLAT  "
    elif [ "$unique_count" -lt 25 ]; then
        status="🟡 THIN  "
    else
        status="✅ RICH  "
    fi

    printf "%s | %2d unique colors | %s\n" "$status" "$unique_count" "$rel_path"
done
