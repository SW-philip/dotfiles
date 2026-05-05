#!/usr/bin/env bash
# ~/nixos/tools/find-bad-values.sh

# Get your current active theme name from your config if possible,
# or just scan all of them.
THEME_ROOT="$HOME/nixos/themes"

echo "--- 🔍 Scanning for values that break 'applyTheme' ---"

# Look for attributes that don't have a value between the quotes
grep -rP '=\s*"\s*";' "$THEME_ROOT" --exclude-dir=themesbk

# Look for attributes that are missing the closing quote before the semicolon
grep -rP '=\s*"[^"]*;' "$THEME_ROOT" --exclude-dir=themesbk | grep -v '";'

# Look for attributes that have an extra space before the # (this breaks many Nix hex parsers)
grep -rP '=\s*"\s+#' "$THEME_ROOT" --exclude-dir=themesbk
