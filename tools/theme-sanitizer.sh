#!/usr/bin/env bash

THEME_ROOT="$HOME/nixos/themes"
MASTER_FILE="$THEME_ROOT/Rose-Pine/main/palette-main.nix"

echo "--- 🧼 Sanitizing All Palettes ---"

find "$THEME_ROOT" -name "*.nix" -not -path "*/themesbk/*" | while read -r theme_file; do
    echo "Processing: $(basename "$theme_file")"

    # 1. Grab only valid KEY = "VALUE"; lines (ignoring the path-prefixed garbage)
    # 2. Grab valid comments
    grep -P '^[[:space:]]*[A-Z0-9_]+\s*=' "$theme_file" > /tmp/sanitized.nix

    # 3. Add back missing keys from Main to ensure the build doesn't fail
    grep -oP '^[[:space:]]*\K[A-Z0-9_]+(?=[[:space:]]*=)' "$MASTER_FILE" | while read -r key; do
        if ! grep -qP "^\s*$key\s*=" /tmp/sanitized.nix; then
            grep -P "^\s*$key\s*=" "$MASTER_FILE" >> /tmp/sanitized.nix
        fi
    done

    # 4. Wrap in braces and overwrite
    { echo "{"; cat /tmp/sanitized.nix; echo "}"; } > "$theme_file"
done

rm /tmp/sanitized.nix
echo "--- ✅ Cleanup Complete. Your 'nrs' build should now work. ---"
