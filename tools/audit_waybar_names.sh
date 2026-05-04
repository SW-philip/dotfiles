#!/usr/bin/env bash

WAYBAR_DIR="$HOME/nixos/home/waybar"
DEFAULT_NIX="$WAYBAR_DIR/default.nix"

echo "--- 🔍 Auditing Waybar Module Names ---"

# 1. Get all "custom/xxx" modules mentioned in the layout of default.nix
mapfile -t layout_modules < <(grep -oP '"custom/[\w\-_]+"' "$DEFAULT_NIX" | sort -u | tr -d '"')

if [ ${#layout_modules[@]} -eq 0 ]; then
    echo "❌ Could not find any custom modules in $DEFAULT_NIX."
    exit 1
fi

echo "Found ${#layout_modules[@]} custom modules in your layout. Checking definitions..."
echo "--------------------------------------------------------"

for mod in "${layout_modules[@]}"; do
    # Search all .nix files in the directory for the definition of this module
    # We look for the pattern: ."custom/name" = 
    definition_file=$(grep -rl ".\"$mod\" =" "$WAYBAR_DIR" --exclude="default.nix")

    if [ -n "$definition_file" ]; then
        echo -e "✅ \033[0;32mMATCH:\033[0m $mod"
        echo "   Defined in: $(basename "$definition_file")"
    else
        # If not found, try to find a "fuzzy" match to suggest a fix
        base_name=$(echo "$mod" | sed 's/custom\///')
        fuzzy_match=$(grep -rl ".\"custom/.*$base_name.*\" =" "$WAYBAR_DIR" --exclude="default.nix" | head -n 1)
        
        echo -e "❌ \033[0;31mSTALE/MISSING:\033[0m $mod"
        if [ -n "$fuzzy_match" ]; then
            actual_key=$(grep -oP '"custom/[\w\-_]+"' "$fuzzy_match" | head -n 1 | tr -d '"')
            echo "   💡 Suggestion: In $(basename "$fuzzy_match"), you used \"$actual_key\"."
            echo "      Update your default.nix layout to match!"
        else
            echo "   ⚠️  No definition found for this key in any .nix file."
        fi
    fi
    echo ""
done

echo "--------------------------------------------------------"
echo "Audit Complete."