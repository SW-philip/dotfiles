#!/usr/bin/env bash

THEME_ROOT="$HOME/nixos/themes"

echo "--- 🕵️ Hunting for the 'Index 0' Culprit ---"

find "$THEME_ROOT" -name "*.nix" -not -path "*/themesbk/*" | while read -r file; do
    # Check for missing # in hex codes (common culprit for string-slicing errors)
    if grep -qP '=\s*"[0-9a-fA-F]{6}"' "$file"; then
        echo "🚨 MISSING HASH FOUND: $file"
        grep -nP '=\s*"[0-9a-fA-F]{6}"' "$file"
    fi

    # Check for path corruption (leftovers from the rogue script)
    if grep -q "/home/prepko" "$file"; then
        echo "🚨 PATH CORRUPTION FOUND: $file"
        grep -n "/home/prepko" "$file"
    fi

    # Check for empty values
    if grep -qP '=\s*"";' "$file"; then
        echo "🚨 EMPTY ATTRIBUTE FOUND: $file"
        grep -nP '=\s*"";' "$file"
    fi
done

echo "----------------------------------------"
echo "If no files appeared, check for a missing closing brace '}' at the end of your files."
