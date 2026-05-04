#!/usr/bin/env bash
# make-lix-wallpaper.sh — SVG-based (Flavor-focused)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ASSETS="$REPO_DIR/assets"

THEME_ARG="${1:-}"
OUTDIR_ARG="${2:-}"

if [[ -z "$THEME_ARG" ]]; then
    echo "Usage: $0 <theme-slug-or-path> [output-dir]"
    exit 1
fi

# ── 1. Locate Theme Directory ───────────────────────────────────────────────
if [[ -d "$THEME_ARG" ]]; then
    THEME_DIR="$(cd "$THEME_ARG" && pwd)"
    THEME="$(basename "$THEME_DIR")"
else
    THEME="$THEME_ARG"
    THEME_DIR=$(find "$REPO_DIR/themes" -maxdepth 2 -type d -name "$THEME" | head -1)
    if [[ -z "$THEME_DIR" ]]; then
        echo "❌ No theme directory found for '$THEME_ARG'"
        exit 1
    fi
fi

# ── 2. Load and Normalize Colors ───────────────────────────────────────────
PALETTE_SH=$(find "$THEME_DIR" -name "palette-*.sh" | head -n1)

# Default Fallbacks (Prevents B&W if variables are missing)
BG_DARK="#1a1a1a"; BG_LIGHT="#2a2a2a"
ICE_SHADOW="#3d2205"; ICE_MID="#d4a030"; ICE_HIGHLIGHT="#fff8e0"
CONE_SHADOW="#965a28"; CONE_MID="#d28e46"; STICKER_COLOR="#ffffff"

if [[ -f "$PALETTE_SH" ]]; then
    source "$PALETTE_SH"

    # Flavor Colors (Magenta/Purple tones)[cite: 1]
    ICE_SHADOW="${BASE:-$ICE_SHADOW}"
    ICE_MID="${LOVE:-${ROSE:-${PINE:-$ICE_MID}}}"
    ICE_HIGHLIGHT="${FOAM:-${GOLD:-${IRIS:-$ICE_HIGHLIGHT}}}"

    # Cone Colors (Orange/Tan tones)[cite: 1]
    CONE_SHADOW="${GOLD:-#ef7627}"
    CONE_MID="${ROSE:-#ff9a56}"
fi

# Apply manual overrides if they exist
if [[ -f "$THEME_DIR/wallpaper-colors.sh" ]]; then
    echo "🔧 Applying manual overrides from wallpaper-colors.sh"
    source "$THEME_DIR/wallpaper-colors.sh"
fi

# ── 3. Setup Environment ───────────────────────────────────────────────────
SLUG=$(echo "$THEME" | sed 's/\([A-Z]\)/-\L\1/g' | sed 's/^-//' | tr '[:upper:]' '[:lower:]')
OUT="${OUTDIR_ARG:-$THEME_DIR}/wallpaper-${SLUG}.png"
W=1920; H=1080
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Ensure the source SVG exists
SOURCE_SVG="$ASSETS/just-the-cone-web.svg"
if [[ ! -f "$SOURCE_SVG" ]]; then
    echo "❌ Error: Source SVG not found at $SOURCE_SVG"
    echo "   Please ensure 'just-the-cone-web.svg' exists in your assets folder."
    exit 1
fi

export TEMP_SVG="$TMP/theme-processed.svg"
export ICE_SHADOW ICE_MID ICE_HIGHLIGHT CONE_SHADOW CONE_MID STICKER_COLOR

cp "$SOURCE_SVG" "$TEMP_SVG"

# ── 4. SVG Color Injection ──────────────────────────────────────────────────
echo "🎨 Injecting colors into SVG for: $THEME"

# EXPLICITLY EXPORT these so Python's os.environ can see them
export ICE_SHADOW ICE_MID ICE_HIGHLIGHT CONE_SHADOW CONE_MID STICKER_COLOR

python3 - <<'PYEOF'
import os
import re
import sys

def get_color(var_name, fallback):
    val = os.environ.get(var_name)
    if not val or val.strip() == "":
        return fallback
    return val

# Mapping the EXACT hex codes found in the Lix SVG to your theme variables
# These match the paths in the SVG you provided:
# #a30262 -> Deep Purple (Shadow)
# #b55690 -> Medium Pink (Mid)
# #d162a4 -> Light Pink (Highlight)
# #ef7627 -> Dark Orange (Cone Shadow)
# #ff9a56 -> Light Orange (Cone Mid)
replacements = [
    ('#a30262', get_color('ICE_SHADOW', '#a30262')),    # Dark Magenta Shadow
    ('#b55690', get_color('ICE_MID', '#b55690')),       # Medium Purple
    ('#d162a4', get_color('ICE_HIGHLIGHT', '#d162a4')), # Light Pink Highlight
    ('#ef7627', get_color('CONE_SHADOW', '#ef7627')),   # Darker Orange Cone
    ('#ff9a56', get_color('CONE_MID', '#ff9a56')),      # Lighter Orange Cone
]

temp_path = os.environ.get('TEMP_SVG')

try:
    with open(temp_path, 'r') as f:
        svg = f.read()

    # Replace the specific hex codes
    for src, dst in replacements:
        svg = re.sub(re.escape(src), dst, svg, flags=re.IGNORECASE)

    # Force sticker logo (white parts) to STICKER_COLOR
    # We look for fill="#fff" or fill='#fff' or fill="white"
    # The SVG has: style="fill:#fff" in the top two paths
    sticker_color = get_color('STICKER_COLOR', '#ffffff')

    # Replace white fills in the specific paths (the "sticker" parts)
    # Using a regex to catch fill="#fff" or fill='#fff'
    svg = re.sub(r'fill=["\']#fff["\']', f'fill="{sticker_color}"', svg)
    svg = re.sub(r'fill=["\']white["\']', f'fill="{sticker_color}"', svg, flags=re.IGNORECASE)

    with open(temp_path, 'w') as f:
        f.write(svg)

except Exception as e:
    print(f"❌ SVG Injection Error: {e}")
    sys.exit(1)
PYEOF

# ── 5. Render (using resvg) ────────────────────────────────────────────────
echo "📸 Preparing SVG background and rendering..."

# 1. Standardize the header to ensure viewBox is correct
sed -i 's|<svg[^>]*>|<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 1080">|' "$TEMP_SVG"

# 2. Create the background gradient and centering group
# We inject a radial gradient background and wrap the original content in a transform group
BG_DEFS="<defs><radialGradient id='bgGradient' cx='50%' cy='50%' r='50%'><stop offset='0%' style='stop-color:${BG_LIGHT}' /><stop offset='100%' style='stop-color:${BG_DARK}' /></radialGradient></defs>"
BG_RECT="<rect width='100%' height='100%' fill='url(#bgGradient)' />"
# Adjust transform: scale(0.7) and translate(1250, 500) to position the cone
TRANSFORM_GROUP="<g transform='scale(0.7) translate(1250, 500)'>"

# Inject the defs and background rect right after the opening svg tag
# We replace the opening tag with itself + defs + rect + group start
sed -i "s|<svg[^>]*>|&${BG_DEFS}${BG_RECT}${TRANSFORM_GROUP}|" "$TEMP_SVG"

# Close the group before the closing svg tag
sed -i "s|</svg>|</g></svg>|" "$TEMP_SVG"

# 4. Render
if ! command -v resvg &> /dev/null; then
    echo "❌ Error: 'resvg' command not found. Please install it (e.g., 'nix-shell -p resvg')."
    exit 1
fi

resvg "$TEMP_SVG" "$OUT"

echo "✅ Success: $OUT"
