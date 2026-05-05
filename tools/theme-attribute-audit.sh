#!/usr/bin/env bash

THEME_ROOT="$HOME/nixos/themes"
TEMP_SCHEMA="/tmp/theme_schema.txt"

# 1. Create the Universal Schema (all unique keys across all themes)
find "$THEME_ROOT" -name "*.nix" -exec grep -oP '^[[:space:]]*\K[A-Z0-9_]+(?=[[:space:]]*=)' {} + | sort -u > "$TEMP_SCHEMA"

echo "--- Global Theme Audit ---"
echo "Total unique attributes expected: $(wc -l < "$TEMP_SCHEMA")"
echo "--------------------------"

# 2. Audit each .nix file
find "$THEME_ROOT" -name "*.nix" | while read -r theme_file; do
    # Extract keys from the current file
    grep -oP '^[[:space:]]*\K[A-Z0-9_]+(?=[[:space:]]*=)' "$theme_file" | sort > /tmp/current_keys

    # Compare against schema
    MISSING=$(comm -23 "$TEMP_SCHEMA" /tmp/current_keys)

    if [[ -n "$MISSING" ]]; then
        # Use family/theme folder names for the report
        rel_path=$(echo "$theme_file" | sed "s|$THEME_ROOT/||")
        echo "❌ $rel_path is missing:"
        echo "$MISSING" | sed 's/^/  - /'
        echo ""
    else
        echo "✅ $(echo "$theme_file" | sed "s|$THEME_ROOT/||") is complete."
    fi
done

rm "$TEMP_SCHEMA" /tmp/current_keys
