#!/usr/bin/env bash
# ============================================================
# extract-waybar-colors.sh
# Pulls all hardcoded color values from the nixos repo and
# shows where each is used
# ============================================================

REPO_DIR="${1:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo "$HOME/nixos")}"

echo "=== NIXOS REPO COLOR AUDIT ==="
echo "Scanning: $REPO_DIR"
echo ""

# Find all hex colors across all relevant file types, excluding .git and generated output
echo "=== ALL HEX COLORS FOUND ==="
grep -rh \
  --include="*.css" --include="*.nix" --include="*.sh" \
  --include="*.py" --include="*.html" --include="*.ini" \
  --exclude-dir=".git" --exclude-dir="output" \
  -oE '#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?' "$REPO_DIR" \
  | tr '[:upper:]' '[:lower:]' \
  | sort | uniq -c | sort -rn \
  | awk '{printf "  %3dx  %s\n", $1, $2}'

echo ""
echo "=== COLORS BY FILE ==="
while IFS= read -r -d '' f; do
  colors=$(grep -oE '#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?' "$f" 2>/dev/null | sort -u)
  if [[ -n "$colors" ]]; then
    echo ""
    echo "--- ${f/$HOME/~} ---"
    while IFS= read -r color; do
      grep -in "$color" "$f" | sed "s/^/  /" | head -5
    done <<< "$colors"
  fi
done < <(find "$REPO_DIR" \
  -not -path "*/.git/*" \
  -not -path "*/output/*" \
  \( -name "*.css" -o -name "*.nix" -o -name "*.sh" \
     -o -name "*.py" -o -name "*.html" -o -name "*.ini" \) \
  -print0)

echo ""
echo "=== ROSE PINE PALETTE CHECK ==="
echo "Expected Rose Pine colors and their usage across the repo:"

declare -A PALETTE=(
  ["#191724"]="Base"
  ["#1f1d2e"]="Surface"
  ["#26233a"]="Overlay"
  ["#403d52"]="HighlightMed"
  ["#524f67"]="HighlightHigh"
  ["#6e6a86"]="Muted"
  ["#908caa"]="Subtle"
  ["#e0def4"]="Text"
  ["#eb6f92"]="Love"
  ["#f6c177"]="Gold"
  ["#9ccfd8"]="Foam"
  ["#c4a7e7"]="Iris"
  ["#31748f"]="Pine"
  ["#ebbcba"]="Rose"
  ["#21202e"]="HighlightLow"
)

for hex in "${!PALETTE[@]}"; do
  name="${PALETTE[$hex]}"
  count=$(grep -rih \
    --include="*.css" --include="*.nix" --include="*.sh" \
    --include="*.py" --include="*.html" --include="*.ini" \
    --exclude-dir=".git" --exclude-dir="output" \
    "$hex" "$REPO_DIR" 2>/dev/null | wc -l)
  if (( count > 0 )); then
    printf "  ✓ %-10s  %-18s  used %dx\n" "$hex" "$name" "$count"
  else
    printf "  ✗ %-10s  %-18s  NOT USED\n" "$hex" "$name"
  fi
done | sort

echo ""
echo "=== COLORS NOT IN ROSE PINE PALETTE ==="
echo "(hardcoded values that don't match any named palette color)"

declare -A ALL_PALETTE_VALS
for hex in "${!PALETTE[@]}"; do
  ALL_PALETTE_VALS["${hex,,}"]=1
done

grep -rh \
  --include="*.css" --include="*.nix" --include="*.sh" \
  --include="*.py" --include="*.html" --include="*.ini" \
  --exclude-dir=".git" --exclude-dir="output" \
  -oE '#[0-9a-fA-F]{6}' "$REPO_DIR" 2>/dev/null \
  | tr '[:upper:]' '[:lower:]' \
  | sort -u \
  | while IFS= read -r color; do
    if [[ -z "${ALL_PALETTE_VALS[$color]+_}" ]]; then
      count=$(grep -rih \
        --include="*.css" --include="*.nix" --include="*.sh" \
        --include="*.py" --include="*.html" --include="*.ini" \
        --exclude-dir=".git" --exclude-dir="output" \
        "$color" "$REPO_DIR" 2>/dev/null | wc -l)
      printf "  %-10s  used %dx\n" "$color" "$count"
    fi
  done
