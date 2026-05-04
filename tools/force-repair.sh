#!/usr/bin/env bash
# ~/nixos/tools/find-empty-hex.sh

THEME_FILE=$(grep -r "palette-" ~/nixos/themes | head -n 1 | cut -d: -f1)
echo "--- Checking Active Palette: $THEME_FILE ---"

# Look for any value that isn't exactly a # followed by 6 hex chars
grep -P '=\s*"(?!#[0-9a-fA-F]{6}";).+"' "$THEME_FILE"
