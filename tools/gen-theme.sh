#!/usr/bin/env bash

# Usage: ./gen-theme.sh "Family" "ThemeName" "#BaseHex" "#AccentHex"
FAMILY=$1
THEME=$2
BASE_SEED=$3
ACCENT_SEED=$4

# (Placeholder logic - requires 'pastel' or similar color tool)
# In a real version, we'd use:
# SURFACE=$(pastel lighten 0.05 "$BASE_SEED")
# OVERLAY=$(pastel lighten 0.10 "$BASE_SEED")

echo "Generating $THEME for family $FAMILY..."

# Create directory
mkdir -p "$HOME/nixos/themes/$FAMILY/$THEME"

# Create the file using a template that injects your seeds
cat <<EOF > "$HOME/nixos/themes/$FAMILY/$THEME/palette-$(echo $THEME | tr '[:upper:]' '[:lower:]').nix"
{
  # Generated from Seed: $BASE_SEED / $ACCENT_SEED
  BASE    = "$BASE_SEED";
  LOVE    = "$ACCENT_SEED";

  # Structural (Hard-coded logic for now)
  SURFACE = "$BASE_SEED"; # To be calculated
  TEXT    = "#ffffff";

  # ... The rest of the 60+ attributes would be filled here ...
}
EOF

echo "✅ Generation complete. Run harmonize-themes.sh to fill in the gaps."
