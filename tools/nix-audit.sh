#!/usr/bin/env bash

# nix-audit.sh: Scans Nix files for env vars and packages to identify consolidation candidates.

TARGET_DIR=${1:-.}

echo "--- NIX ENVIRONMENT VARIABLE & PACKAGE AUDIT ---"
echo "Target: $(realpath "$TARGET_DIR")"
echo ""

# 1. Find Environment Variables (NixOS and Home Manager patterns)
echo "## [ENVIRONMENT VARIABLES]"
rg --json -e 'sessionVariables\s*=\s*\{' -e 'environment\.variables\s*=\s*\{' "$TARGET_DIR" | \
jq -r 'select(.type=="match") | .data.path.text as $path | .data.lines.text as $line | "\($path): \($line)"' | \
sed 's/^[[:space:]]*//'

# 2. Extract specific variable keys to find duplicates/universals
echo -e "\n## [VAR KEYS IDENTIFIED]"
rg -oP '(?<=\{|\s)[A-Z0-9_]+(?=\s*=)' "$TARGET_DIR" | sort | uniq -c | sort -nr

# 3. Find Package Lists (systemPackages and home.packages)
echo -e "\n## [PACKAGE DECLARATIONS]"
rg --json -e 'systemPackages\s*=\s*with pkgs; \[' -e 'home\.packages\s*=\s*\[' "$TARGET_DIR" | \
jq -r 'select(.type=="match") | .data.path.text' | uniq

# 4. Find XDG-specific configurations
echo -e "\n## [XDG CONFIGURATIONS]"
rg -l "xdg\." "$TARGET_DIR"

echo -e "\n--- END OF AUDIT ---"
