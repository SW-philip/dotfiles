#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration & Defaults
# -----------------------------------------------------------------------------
DEFAULT_FOLDER="Lix"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARMONIZER="$SCRIPT_DIR/harmonize-themes.sh"

# -----------------------------------------------------------------------------
# Argument Parsing
# -----------------------------------------------------------------------------
FOLDER_ARG=""
THEME_NAME=""
PRIMARY_COLOR=""
SECONDARY_COLOR=""
PINE_COLOR=""
IRIS_COLOR=""
GOLD_COLOR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --folder|-f)
            FOLDER_ARG="$2"
            shift 2
            ;;
        *)
            if [[ -z "$THEME_NAME" ]]; then
                THEME_NAME="$1"
            elif [[ -z "$PRIMARY_COLOR" ]]; then
                PRIMARY_COLOR="$1"
            elif [[ -z "$SECONDARY_COLOR" ]]; then
                SECONDARY_COLOR="$1"
            elif [[ -z "$PINE_COLOR" ]]; then
                PINE_COLOR="$1"
            elif [[ -z "$IRIS_COLOR" ]]; then
                IRIS_COLOR="$1"
            elif [[ -z "$GOLD_COLOR" ]]; then
                GOLD_COLOR="$1"
            else
                echo "Error: Too many arguments."
                exit 1
            fi
            shift
            ;;
    esac
done

TARGET_FOLDER="${FOLDER_ARG:-$DEFAULT_FOLDER}"

# -----------------------------------------------------------------------------
# Interactive Prompts
# -----------------------------------------------------------------------------
if [[ -z "$THEME_NAME" ]]; then
    read -rp "🎨 Enter Theme Name: " THEME_NAME
fi

if [[ -z "$PRIMARY_COLOR" ]]; then
    read -rp "🎨 Enter Primary Color / Base (Hex): " PRIMARY_COLOR
fi

if [[ -z "$SECONDARY_COLOR" ]]; then
    read -rp "🎨 Enter Love / Secondary Color (Hex): " SECONDARY_COLOR
fi

if [[ -z "$PINE_COLOR" ]]; then
    read -rp "🌲 Enter Pine / Green Color (Hex): " PINE_COLOR
fi

if [[ -z "$IRIS_COLOR" ]]; then
    read -rp "🔮 Enter Iris / Accent Color (Hex): " IRIS_COLOR
fi

if [[ -z "$GOLD_COLOR" ]]; then
    read -rp "✨ Enter Gold / Warm Color (Hex): " GOLD_COLOR
fi

# Validation
if [[ -z "$THEME_NAME" || -z "$PRIMARY_COLOR" || -z "$SECONDARY_COLOR" || -z "$PINE_COLOR" || -z "$IRIS_COLOR" || -z "$GOLD_COLOR" ]]; then
    echo "❌ Error: Missing required inputs."
    exit 1
fi

# Basic Hex validation
HEX_RE='^#[0-9a-fA-F]{6}$'
for col in "$PRIMARY_COLOR" "$SECONDARY_COLOR" "$PINE_COLOR" "$IRIS_COLOR" "$GOLD_COLOR"; do
    if [[ ! "$col" =~ $HEX_RE ]]; then
        echo "❌ Error: '$col' is not a valid Hex color (e.g., #RRGGBB)."
        exit 1
    fi
done

# -----------------------------------------------------------------------------
# Path Setup
# -----------------------------------------------------------------------------
BASE_PATH="$HOME/nixos/themes/$TARGET_FOLDER"
THEME_DIR="$BASE_PATH/$THEME_NAME"

if [[ ! -d "$BASE_PATH" ]]; then
    mkdir -p "$BASE_PATH"
fi
if [[ ! -d "$THEME_DIR" ]]; then
    mkdir -p "$THEME_DIR"
fi

SLUG=$(echo "$THEME_NAME" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')

PALETTE_NIX="$THEME_DIR/palette-$SLUG.nix"
PALETTE_SH="$THEME_DIR/palette-$SLUG.sh"

echo "🎨 Generating $THEME_NAME (slug: $SLUG)..."

# -----------------------------------------------------------------------------
# Color Role Rules
# -----------------------------------------------------------------------------
# PRIMARY  — the canvas. Large-area background. Low-to-medium saturation works
#            well; this is what the eye adapts to. Dark or light determines
#            the overall mode. No contrast requirement against itself.
#
# SECONDARY — the personality. Main accent color (LOVE). Must contrast against
#             PRIMARY at ≥4.5:1 (WCAG AA text-level). Drives ROSE/GOLD/PINE/FOAM
#             and semantic state colors. Should be vivid/saturated.
#
# ACCENT    — the highlight. Secondary accent color (IRIS). Must contrast against
#             PRIMARY at ≥3:1 (WCAG AA large-UI-level). Must differ from
#             SECONDARY by ≥30° of hue or they'll appear identical on the bar.
#             Drives IRIS, ACCENT_PRIMARY, border highlights.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Math Engine: Hex <-> HSL Conversion & Adjustment
# -----------------------------------------------------------------------------

# Helper: Convert Hex to RGB array (returns space separated R G B)
hex_to_rgb() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    echo "$r $g $b"
}

# Helper: Convert RGB to Hex
rgb_to_hex() {
    printf "#%02x%02x%02x" "$1" "$2" "$3"
}

# Helper: Extract R,G,B CSV string from hex (for rgba() usage in CSS)
hex_to_rgb_csv() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    echo "$r,$g,$b"
}

# Main Calculation Function
# Args: hex_color, operation (lighten|darken|desaturate|saturate|shift_hue), amount
calc_color() {
    local hex=$1
    local op=$2
    local amt=$3

    read -r r g b <<< "$(hex_to_rgb "$hex")"

    awk -v r="$r" -v g="$g" -v b="$b" -v op="$op" -v amt="$amt" 'BEGIN {
        # Normalize 0-1
        r_n = r/255; g_n = g/255; b_n = b/255

        # Find Max/Min
        max = (r_n>g_n && r_n>b_n) ? r_n : ((g_n>b_n) ? g_n : b_n)
        min = (r_n<g_n && r_n<b_n) ? r_n : ((g_n<b_n) ? g_n : b_n)
        l = (max + min) / 2

        if (max == min) {
            s = 0; h_hue = 0
        } else {
            d = max - min
            s = (l > 0.5) ? d / (2 - max - min) : d / (max + min)

            if (max == r_n) h_hue = (g_n - b_n) / d + (g_n < b_n ? 6 : 0)
            else if (max == g_n) h_hue = (b_n - r_n) / d + 2
            else h_hue = (r_n - g_n) / d + 4
            h_hue /= 6
        }

        # Apply Operation
        if (op == "lighten") {
            l = l + (amt / 100)
        } else if (op == "darken") {
            l = l - (amt / 100)
        } else if (op == "desaturate") {
            s = s * (1 - (amt / 100))
        } else if (op == "saturate") {
            s = s + (1 - s) * (amt / 100)
        } else if (op == "shift_hue") {
            h_hue = (h_hue + (amt / 360)) % 1
            if (h_hue < 0) h_hue += 1
        }

        # Clamp
        if (l > 1) l = 1; if (l < 0) l = 0
        if (s > 1) s = 1; if (s < 0) s = 0

        # HSL to RGB (Inlined logic)
        if (s == 0) {
            r_out = g_out = b_out = l
        } else {
            q = (l < 0.5) ? l * (1 + s) : l + s - l * s
            p = 2 * l - q

            t1 = h_hue + 1/3
            if (t1 < 0) t1 += 1; if (t1 > 1) t1 -= 1
            if (t1 < 1/6) r_out = p + (q - p) * 6 * t1
            else if (t1 < 1/2) r_out = q
            else if (t1 < 2/3) r_out = p + (q - p) * (2/3 - t1) * 6
            else r_out = p

            t2 = h_hue
            if (t2 < 0) t2 += 1; if (t2 > 1) t2 -= 1
            if (t2 < 1/6) g_out = p + (q - p) * 6 * t2
            else if (t2 < 1/2) g_out = q
            else if (t2 < 2/3) g_out = p + (q - p) * (2/3 - t2) * 6
            else g_out = p

            t3 = h_hue - 1/3
            if (t3 < 0) t3 += 1; if (t3 > 1) t3 -= 1
            if (t3 < 1/6) b_out = p + (q - p) * 6 * t3
            else if (t3 < 1/2) b_out = q
            else if (t3 < 2/3) b_out = p + (q - p) * (2/3 - t3) * 6
            else b_out = p
        }

        printf "%d %d %d", int(r_out*255+0.5), int(g_out*255+0.5), int(b_out*255+0.5)
    }'
}

# Returns WCAG relative luminance (0.0–1.0) for a hex color
relative_luminance() {
    local hex=$1
    read -r r g b <<< "$(hex_to_rgb "$hex")"
    awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN {
        split("" r " " g " " b, ch, " ")
        for (i = 1; i <= 3; i++) {
            c = (i==1 ? r : (i==2 ? g : b)) / 255
            lin[i] = (c <= 0.04045) ? c/12.92 : ((c + 0.055)/1.055)^2.4
        }
        printf "%.6f", 0.2126*lin[1] + 0.7152*lin[2] + 0.0722*lin[3]
    }'
}

# Returns WCAG contrast ratio between two hex colors (e.g. "4.52")
contrast_ratio() {
    local l1 l2
    l1=$(relative_luminance "$1")
    l2=$(relative_luminance "$2")
    awk -v l1="$l1" -v l2="$l2" 'BEGIN {
        if (l1 < l2) { t=l1; l1=l2; l2=t }
        printf "%.2f", (l1 + 0.05) / (l2 + 0.05)
    }'
}

# Returns the hue angle (0–359) for a hex color
get_hue() {
    local hex=$1
    read -r r g b <<< "$(hex_to_rgb "$hex")"
    awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN {
        r_n=r/255; g_n=g/255; b_n=b/255
        max=(r_n>g_n&&r_n>b_n)?r_n:((g_n>b_n)?g_n:b_n)
        min=(r_n<g_n&&r_n<b_n)?r_n:((g_n<b_n)?g_n:b_n)
        if (max==min) { print 0; exit }
        d=max-min
        if (max==r_n) h=(g_n-b_n)/d+(g_n<b_n?6:0)
        else if (max==g_n) h=(b_n-r_n)/d+2
        else h=(r_n-g_n)/d+4
        h/=6
        printf "%d", int(h*360+0.5)
    }'
}

# Nudge a color's lightness in $dir (lighten|darken) by 3% per step until
# it meets $target contrast ratio against $bg. Warns and returns best if
# max iterations exhausted. Never hard-exits — a degraded theme beats nothing.
auto_boost() {
    local color="$1" bg="$2" target="$3" dir="$4"
    local current="$color"
    local step=3 max_iter=20

    for (( i=0; i<max_iter; i++ )); do
        local ratio pass
        ratio=$(contrast_ratio "$current" "$bg")
        pass=$(awk -v r="$ratio" -v t="$target" 'BEGIN { print (r >= t) ? 1 : 0 }')
        [[ "$pass" == "1" ]] && { echo "$current"; return 0; }
        local adjusted
        adjusted=$(calc_color "$current" "$dir" "$step")
        current=$(rgb_to_hex $adjusted)
    done

    local final_ratio
    final_ratio=$(contrast_ratio "$current" "$bg")
    echo "⚠️  Could not reach ${target}:1 for $color vs $bg (best: ${final_ratio}:1)" >&2
    echo "$current"
}

# Helper to determine text color based on brightness
get_text_color() {
    local hex=$1
    read -r r g b <<< "$(hex_to_rgb "$hex")"
    local brightness=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
    if (( brightness > 155 )); then
        echo "#1a1a1a"
    else
        echo "#ffffff"
    fi
}

# Helper: returns "dark" or "light" based on perceived brightness of a hex color
theme_mode() {
    local hex=$1
    read -r r g b <<< "$(hex_to_rgb "$hex")"
    local brightness=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
    if (( brightness < 128 )); then
        echo "dark"
    else
        echo "light"
    fi
}

# -----------------------------------------------------------------------------
# Contrast Validation & Auto-Boost
# -----------------------------------------------------------------------------
echo "🔍 Validating contrast ratios..."

MODE=$(theme_mode "$PRIMARY_COLOR")

# Boost direction: for dark themes, accents need to be lighter to stand out;
# for light themes, accents need to be darker.
BOOST_DIR="lighten"
[[ "$MODE" == "light" ]] && BOOST_DIR="darken"

# --- Secondary vs Primary (4.5:1 — text/icon contrast) ---
SEC_RATIO=$(contrast_ratio "$SECONDARY_COLOR" "$PRIMARY_COLOR")
echo "   Secondary vs Primary: ${SEC_RATIO}:1  (target ≥4.5)"
if awk -v r="$SEC_RATIO" 'BEGIN { exit !(r < 4.5) }'; then
    echo "   ⚡ Boosting secondary to meet 4.5:1..."
    SECONDARY_COLOR=$(auto_boost "$SECONDARY_COLOR" "$PRIMARY_COLOR" 4.5 "$BOOST_DIR")
    echo "   → $SECONDARY_COLOR  ($(contrast_ratio "$SECONDARY_COLOR" "$PRIMARY_COLOR"):1)"
fi

# --- Pine vs Primary (3.0:1) ---
PINE_RATIO=$(contrast_ratio "$PINE_COLOR" "$PRIMARY_COLOR")
echo "   Pine vs Primary:      ${PINE_RATIO}:1  (target ≥3.0)"
if awk -v r="$PINE_RATIO" 'BEGIN { exit !(r < 3.0) }'; then
    echo "   ⚡ Boosting pine to meet 3.0:1..."
    PINE_COLOR=$(auto_boost "$PINE_COLOR" "$PRIMARY_COLOR" 3.0 "$BOOST_DIR")
    echo "   → $PINE_COLOR  ($(contrast_ratio "$PINE_COLOR" "$PRIMARY_COLOR"):1)"
fi

# --- Iris vs Primary (3.0:1 — large-element contrast) ---
IRIS_RATIO=$(contrast_ratio "$IRIS_COLOR" "$PRIMARY_COLOR")
echo "   Iris vs Primary:      ${IRIS_RATIO}:1  (target ≥3.0)"
if awk -v r="$IRIS_RATIO" 'BEGIN { exit !(r < 3.0) }'; then
    echo "   ⚡ Boosting iris to meet 3.0:1..."
    IRIS_COLOR=$(auto_boost "$IRIS_COLOR" "$PRIMARY_COLOR" 3.0 "$BOOST_DIR")
    echo "   → $IRIS_COLOR  ($(contrast_ratio "$IRIS_COLOR" "$PRIMARY_COLOR"):1)"
fi

# --- Gold vs Primary (3.0:1) ---
GOLD_RATIO=$(contrast_ratio "$GOLD_COLOR" "$PRIMARY_COLOR")
echo "   Gold vs Primary:      ${GOLD_RATIO}:1  (target ≥3.0)"
if awk -v r="$GOLD_RATIO" 'BEGIN { exit !(r < 3.0) }'; then
    echo "   ⚡ Boosting gold to meet 3.0:1..."
    GOLD_COLOR=$(auto_boost "$GOLD_COLOR" "$PRIMARY_COLOR" 3.0 "$BOOST_DIR")
    echo "   → $GOLD_COLOR  ($(contrast_ratio "$GOLD_COLOR" "$PRIMARY_COLOR"):1)"
fi

# --- Hue separation checks (≥30° recommended between accent pairs) ---
HUE_SEC=$(get_hue "$SECONDARY_COLOR")
HUE_IRIS=$(get_hue "$IRIS_COLOR")
HUE_DIFF=$(awk -v s="$HUE_SEC" -v a="$HUE_IRIS" 'BEGIN {
    d = (s > a) ? s-a : a-s
    if (d > 180) d = 360 - d
    print d
}')
echo "   Love hue: ${HUE_SEC}°   Iris hue: ${HUE_IRIS}°   Separation: ${HUE_DIFF}°  (recommend ≥30°)"
if (( HUE_DIFF < 30 )); then
    echo "   ⚠️  Love and Iris are only ${HUE_DIFF}° apart — they may look identical on the bar."
fi

echo "✅ Contrast check complete."
echo ""

# ── Mode-dependent shadow and icon shadow values ──────────────────────────────
if [[ "$MODE" == "dark" ]]; then
    ICON_SHADOW_VAL="0 1px 2px rgba(0,0,0,0.80)"
    SHADOW_A_OUTER_VAL="0.50"
    SHADOW_A_DROP_VAL="0.55"
    SHADOW_A_HOVER_VAL="0.65"
    INSET_TOP_A_VAL="0.08"
    INSET_BOT_A_VAL="0.30"
    BORDER_TOP_A_VAL="0.07"
else
    ICON_SHADOW_VAL="0 1px 2px rgba(0,0,0,0.35)"
    SHADOW_A_OUTER_VAL="0.10"
    SHADOW_A_DROP_VAL="0.07"
    SHADOW_A_HOVER_VAL="0.10"
    INSET_TOP_A_VAL="0.50"
    INSET_BOT_A_VAL="0.08"
    BORDER_TOP_A_VAL="0.65"
fi

# -----------------------------------------------------------------------------
# Step 1: Generate Raw Template (with placeholders)
# -----------------------------------------------------------------------------
cat <<EOF > "$PALETTE_NIX"
{
  # ── Base ──────────────────────────────────────────────────────
  BASE           = "$PRIMARY_COLOR";
  SURFACE        = "__CALC_SURFACE__";
  OVERLAY        = "__CALC_OVERLAY__";
  HIGHLIGHT_LOW  = "__CALC_HIGHLIGHT_LOW__";
  HIGHLIGHT_MED  = "__CALC_HIGHLIGHT_MED__";
  HIGHLIGHT_HIGH = "__CALC_HIGHLIGHT_HIGH__";

  # ── Text & accents ────────────────────────────────────────────
  MUTED  = "__CALC_MUTED__";
  SUBTLE = "__CALC_SUBTLE__";
  TEXT   = "__CALC_TEXT__";
  LOVE   = "$SECONDARY_COLOR";
  ROSE   = "__CALC_ROSE__";
  GOLD   = "$GOLD_COLOR";
  PINE   = "$PINE_COLOR";
  FOAM   = "__CALC_FOAM__";
  IRIS   = "$IRIS_COLOR";

  # ── Extended — named system-state colors ──────────────────────
  CRITICAL   = "__CALC_CRITICAL__";
  WARNING    = "__CALC_WARNING__";
  CAUTION    = "__CALC_CAUTION__";
  MUTED_ICON = "__CALC_MUTED_ICON__";

  # ── Structural (computed from base) ───────────────────────────
  INACTIVE_BORDER = "__CALC_INACTIVE_BORDER__";
  SHADOW          = "__CALC_SHADOW__";

  # ── Waybar module background tiers ────────────────────────────
  WB_BASE    = "__CALC_WB_BASE__";
  WB_SURFACE = "__CALC_WB_SURFACE__";
  WB_OVERLAY = "__CALC_WB_OVERLAY__";

  # ── Gradient depth anchors ────────────────────────────────────
  GRAD_SURFACE_HI = "__CALC_GRAD_SURFACE_HI__";
  GRAD_SURFACE_LO = "__CALC_GRAD_SURFACE_LO__";
  GRAD_OVERLAY_HI = "__CALC_GRAD_OVERLAY_HI__";
  GRAD_OVERLAY_LO = "__CALC_GRAD_OVERLAY_LO__";
  GRAD_BASE_HI    = "__CALC_GRAD_BASE_HI__";
  GRAD_BASE_LO    = "__CALC_GRAD_BASE_LO__";

  # ── Accent border tints (R,G,B format for rgba()) ────────────
  BORDER_ACCENT_RGB = "__CALC_BORDER_ACCENT_RGB__";
  BORDER_IRIS_RGB   = "__CALC_BORDER_IRIS_RGB__";

  # ── Derived tinted backgrounds ────────────────────────────────
  TINT_PINE_DARK   = "__CALC_TINT_PINE_DARK__";
  TINT_PINE_MID    = "__CALC_TINT_PINE_MID__";
  TINT_CRITICAL_BG = "__CALC_TINT_CRITICAL_BG__";

  # ── State-tinted hover backgrounds ────────────────────────────
  HOVER_MUTED_BG  = "__CALC_HOVER_MUTED_BG__";
  HOVER_TEAL_BG   = "__CALC_HOVER_TEAL_BG__";
  HOVER_GREEN_BG  = "__CALC_HOVER_GREEN_BG__";
  HOVER_GOLD_BG   = "__CALC_HOVER_GOLD_BG__";
  HOVER_ORANGE_BG = "__CALC_HOVER_ORANGE_BG__";

  # ── Bar typography ───────────────────────────────────────────
  FONT_SIZE_BAR = "12px";
  ICON_SHADOW   = "$ICON_SHADOW_VAL";

  # ── Box-shadow composition ───────────────────────────────────
  SHADOW_RGB     = "__CALC_SHADOW_RGB__";
  SHADOW_A_OUTER = "$SHADOW_A_OUTER_VAL";
  SHADOW_A_DROP  = "$SHADOW_A_DROP_VAL";
  SHADOW_A_HOVER = "$SHADOW_A_HOVER_VAL";
  INSET_TOP_A    = "$INSET_TOP_A_VAL";
  INSET_BOT_A    = "$INSET_BOT_A_VAL";
  BORDER_TOP_A   = "$BORDER_TOP_A_VAL";

  # ── Battery (anchored to theme semantic colors) ───────────────
  BATTERY_FULL = "__CALC_BATTERY_FULL__";
  BATTERY_HIGH = "__CALC_BATTERY_HIGH__";
  BATTERY_MED  = "__CALC_BATTERY_MED__";
  BATTERY_LOW  = "__CALC_BATTERY_LOW__";
  BATTERY_CRIT = "__CALC_BATTERY_CRIT__";

  # ── Named accent roles ────────────────────────────────────────
  BORDER_ACCENT    = "__CALC_BORDER_ACCENT__";
  ACCENT_PRIMARY   = "$IRIS_COLOR";
  TEXT_PRIMARY     = "__CALC_TEXT__";
  TEXT_SECONDARY   = "__CALC_SUBTLE__";
  ACCENT_SECONDARY = "__CALC_ACCENT_SECONDARY__";
}
EOF

echo "✅ Created raw template: $PALETTE_NIX"

# -----------------------------------------------------------------------------
# Step 2: Run Math Engine
# -----------------------------------------------------------------------------
echo "🧮 Calculating harmonious palette..."

MODE=$(theme_mode "$PRIMARY_COLOR")
echo "   Theme mode: $MODE"

# ── Base-derived colors ───────────────────────────────────────────────────────
SURFACE_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 10)
SURFACE_VAL=$(rgb_to_hex $SURFACE_VAL)

OVERLAY_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 20)
OVERLAY_VAL=$(rgb_to_hex $OVERLAY_VAL)

HIGHLIGHT_LOW_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 5)
HIGHLIGHT_LOW_VAL=$(rgb_to_hex $HIGHLIGHT_LOW_VAL)

HIGHLIGHT_MED_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 12)
HIGHLIGHT_MED_VAL=$(rgb_to_hex $HIGHLIGHT_MED_VAL)

HIGHLIGHT_HIGH_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 25)
HIGHLIGHT_HIGH_VAL=$(rgb_to_hex $HIGHLIGHT_HIGH_VAL)

MUTED_VAL=$(calc_color "$PRIMARY_COLOR" "desaturate" 40)
MUTED_VAL=$(rgb_to_hex $MUTED_VAL)
MUTED_VAL=$(calc_color "$MUTED_VAL" "lighten" 30)
MUTED_VAL=$(rgb_to_hex $MUTED_VAL)

SUBTLE_VAL=$(calc_color "$PRIMARY_COLOR" "desaturate" 50)
SUBTLE_VAL=$(rgb_to_hex $SUBTLE_VAL)
SUBTLE_VAL=$(calc_color "$SUBTLE_VAL" "lighten" 40)
SUBTLE_VAL=$(rgb_to_hex $SUBTLE_VAL)

TEXT_VAL=$(get_text_color "$PRIMARY_COLOR")

# ── Structural: border + shadow derived from base ────────────────────────────
# INACTIVE_BORDER: desaturated, subtle step away from base
# SHADOW: darker and more neutral
if [[ "$MODE" == "dark" ]]; then
    INACTIVE_BORDER_VAL=$(calc_color "$PRIMARY_COLOR" "desaturate" 20)
    INACTIVE_BORDER_VAL=$(rgb_to_hex $INACTIVE_BORDER_VAL)
    INACTIVE_BORDER_VAL=$(calc_color "$INACTIVE_BORDER_VAL" "lighten" 12)
    INACTIVE_BORDER_VAL=$(rgb_to_hex $INACTIVE_BORDER_VAL)

    SHADOW_VAL=$(calc_color "$PRIMARY_COLOR" "desaturate" 30)
    SHADOW_VAL=$(rgb_to_hex $SHADOW_VAL)
    SHADOW_VAL=$(calc_color "$SHADOW_VAL" "darken" 8)
    SHADOW_VAL=$(rgb_to_hex $SHADOW_VAL)
else
    INACTIVE_BORDER_VAL=$(calc_color "$PRIMARY_COLOR" "desaturate" 25)
    INACTIVE_BORDER_VAL=$(rgb_to_hex $INACTIVE_BORDER_VAL)
    INACTIVE_BORDER_VAL=$(calc_color "$INACTIVE_BORDER_VAL" "darken" 10)
    INACTIVE_BORDER_VAL=$(rgb_to_hex $INACTIVE_BORDER_VAL)

    SHADOW_VAL=$(calc_color "$PRIMARY_COLOR" "desaturate" 35)
    SHADOW_VAL=$(rgb_to_hex $SHADOW_VAL)
    SHADOW_VAL=$(calc_color "$SHADOW_VAL" "darken" 20)
    SHADOW_VAL=$(rgb_to_hex $SHADOW_VAL)
fi

SHADOW_RGB_VAL=$(hex_to_rgb_csv "$SHADOW_VAL")

# ── Waybar bar tiers: adapt step direction to theme mode ─────────────────────
# Dark themes: bars should be slightly LIGHTER than base (elevated surfaces)
# Light themes: bars should be slightly DARKER than base (recessed panels)
if [[ "$MODE" == "dark" ]]; then
    WB_BASE_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 7)
    WB_BASE_VAL=$(rgb_to_hex $WB_BASE_VAL)
    WB_SURFACE_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 11)
    WB_SURFACE_VAL=$(rgb_to_hex $WB_SURFACE_VAL)
    WB_OVERLAY_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 16)
    WB_OVERLAY_VAL=$(rgb_to_hex $WB_OVERLAY_VAL)
else
    WB_BASE_VAL=$(calc_color "$PRIMARY_COLOR" "darken" 5)
    WB_BASE_VAL=$(rgb_to_hex $WB_BASE_VAL)
    WB_SURFACE_VAL=$(calc_color "$PRIMARY_COLOR" "darken" 8)
    WB_SURFACE_VAL=$(rgb_to_hex $WB_SURFACE_VAL)
    WB_OVERLAY_VAL=$(calc_color "$PRIMARY_COLOR" "darken" 12)
    WB_OVERLAY_VAL=$(rgb_to_hex $WB_OVERLAY_VAL)
fi

# ── Gradient anchors: ±3% around each WB tier ────────────────────────────────
GRAD_BASE_HI_VAL=$(calc_color "$WB_BASE_VAL" "lighten" 3)
GRAD_BASE_HI_VAL=$(rgb_to_hex $GRAD_BASE_HI_VAL)
GRAD_BASE_LO_VAL=$(calc_color "$WB_BASE_VAL" "darken" 3)
GRAD_BASE_LO_VAL=$(rgb_to_hex $GRAD_BASE_LO_VAL)

GRAD_SURFACE_HI_VAL=$(calc_color "$WB_SURFACE_VAL" "lighten" 3)
GRAD_SURFACE_HI_VAL=$(rgb_to_hex $GRAD_SURFACE_HI_VAL)
GRAD_SURFACE_LO_VAL=$(calc_color "$WB_SURFACE_VAL" "darken" 3)
GRAD_SURFACE_LO_VAL=$(rgb_to_hex $GRAD_SURFACE_LO_VAL)

GRAD_OVERLAY_HI_VAL=$(calc_color "$WB_OVERLAY_VAL" "lighten" 3)
GRAD_OVERLAY_HI_VAL=$(rgb_to_hex $GRAD_OVERLAY_HI_VAL)
GRAD_OVERLAY_LO_VAL=$(calc_color "$WB_OVERLAY_VAL" "darken" 3)
GRAD_OVERLAY_LO_VAL=$(rgb_to_hex $GRAD_OVERLAY_LO_VAL)

# ── Secondary-derived accent colors ──────────────────────────────────────────
ROSE_VAL=$(calc_color "$SECONDARY_COLOR" "shift_hue" -20)
ROSE_VAL=$(rgb_to_hex $ROSE_VAL)

# GOLD and PINE are explicit inputs — no derivation needed
GOLD_VAL="$GOLD_COLOR"
PINE_VAL="$PINE_COLOR"

# FOAM: derived from PINE (desaturated + slightly lightened sibling)
FOAM_VAL=$(calc_color "$PINE_COLOR" "desaturate" 25)
FOAM_VAL=$(rgb_to_hex $FOAM_VAL)
FOAM_VAL=$(calc_color "$FOAM_VAL" "lighten" 8)
FOAM_VAL=$(rgb_to_hex $FOAM_VAL)

# ── Iris-derived colors ───────────────────────────────────────────────────────
# IRIS = IRIS_COLOR directly (set in template literal above)
# ACCENT_SECONDARY: slight hue shift from iris for variation
ACCENT_SECONDARY_VAL=$(calc_color "$IRIS_COLOR" "shift_hue" 30)
ACCENT_SECONDARY_VAL=$(rgb_to_hex $ACCENT_SECONDARY_VAL)
ACCENT_SECONDARY_VAL=$(calc_color "$ACCENT_SECONDARY_VAL" "desaturate" 15)
ACCENT_SECONDARY_VAL=$(rgb_to_hex $ACCENT_SECONDARY_VAL)

# ── Border accent RGB values (for rgba() usage) ───────────────────────────────
BORDER_ACCENT_RGB_VAL=$(hex_to_rgb_csv "$SECONDARY_COLOR")
BORDER_IRIS_RGB_VAL=$(hex_to_rgb_csv "$IRIS_COLOR")
BORDER_ACCENT_VAL=$(calc_color "$SECONDARY_COLOR" "darken" 10)
BORDER_ACCENT_VAL=$(rgb_to_hex $BORDER_ACCENT_VAL)

# ── State colors ──────────────────────────────────────────────────────────────
CRITICAL_VAL=$(calc_color "$SECONDARY_COLOR" "shift_hue" -10)
CRITICAL_VAL=$(rgb_to_hex $CRITICAL_VAL)

WARNING_VAL=$(calc_color "$SECONDARY_COLOR" "shift_hue" 35)
WARNING_VAL=$(rgb_to_hex $WARNING_VAL)

CAUTION_VAL=$(calc_color "$SECONDARY_COLOR" "lighten" 20)
CAUTION_VAL=$(rgb_to_hex $CAUTION_VAL)

MUTED_ICON_VAL=$(calc_color "$PRIMARY_COLOR" "desaturate" 20)
MUTED_ICON_VAL=$(rgb_to_hex $MUTED_ICON_VAL)
MUTED_ICON_VAL=$(calc_color "$MUTED_ICON_VAL" "lighten" 15)
MUTED_ICON_VAL=$(rgb_to_hex $MUTED_ICON_VAL)

# ── Battery semantic colors (anchored to theme palette) ───────────────────────
# crit=LOVE(red), low=GOLD(yellow), med=ROSE(pink), high=FOAM(teal), full=PINE(green)
BATTERY_CRIT_VAL="$SECONDARY_COLOR"
BATTERY_LOW_VAL="$GOLD_VAL"
BATTERY_MED_VAL="$ROSE_VAL"
BATTERY_HIGH_VAL="$FOAM_VAL"
BATTERY_FULL_VAL="$PINE_VAL"

# ── Tinted backgrounds ────────────────────────────────────────────────────────
# Dark: very dark tints so bright text (FOAM, CAUTION, CRITICAL) is readable.
# Light: pale washes — same semantic intent but lightened.
if [[ "$MODE" == "dark" ]]; then
    TINT_PINE_DARK_VAL=$(calc_color "$PINE_VAL" "darken" 35)
    TINT_PINE_DARK_VAL=$(rgb_to_hex $TINT_PINE_DARK_VAL)
    TINT_PINE_MID_VAL=$(calc_color "$PINE_VAL" "darken" 32)
    TINT_PINE_MID_VAL=$(rgb_to_hex $TINT_PINE_MID_VAL)
    TINT_CRITICAL_BG_VAL=$(calc_color "$CRITICAL_VAL" "darken" 55)
    TINT_CRITICAL_BG_VAL=$(rgb_to_hex $TINT_CRITICAL_BG_VAL)
else
    TINT_PINE_DARK_VAL=$(calc_color "$PINE_VAL" "lighten" 40)
    TINT_PINE_DARK_VAL=$(rgb_to_hex $TINT_PINE_DARK_VAL)
    TINT_PINE_MID_VAL=$(calc_color "$PINE_VAL" "lighten" 45)
    TINT_PINE_MID_VAL=$(rgb_to_hex $TINT_PINE_MID_VAL)
    TINT_CRITICAL_BG_VAL=$(calc_color "$CRITICAL_VAL" "lighten" 40)
    TINT_CRITICAL_BG_VAL=$(rgb_to_hex $TINT_CRITICAL_BG_VAL)
fi

# ── Hover backgrounds ─────────────────────────────────────────────────────────
# Dark: darken from BASE so bright state-colored text pops against the bg.
# Light: lighten from BASE to keep contrast with dark text.
# Source is always BASE (not accent colors) to keep hover tones in the same
# hue family as the canvas.
if [[ "$MODE" == "dark" ]]; then
    HOVER_MUTED_BG_VAL=$(calc_color "$PRIMARY_COLOR" "darken" 3)
    HOVER_MUTED_BG_VAL=$(rgb_to_hex $HOVER_MUTED_BG_VAL)
    HOVER_TEAL_BG_VAL=$(calc_color "$PRIMARY_COLOR" "darken" 8)
    HOVER_TEAL_BG_VAL=$(rgb_to_hex $HOVER_TEAL_BG_VAL)
    HOVER_GREEN_BG_VAL=$(calc_color "$PRIMARY_COLOR" "darken" 10)
    HOVER_GREEN_BG_VAL=$(rgb_to_hex $HOVER_GREEN_BG_VAL)
    HOVER_GOLD_BG_VAL=$(calc_color "$PRIMARY_COLOR" "darken" 7)
    HOVER_GOLD_BG_VAL=$(rgb_to_hex $HOVER_GOLD_BG_VAL)
    HOVER_ORANGE_BG_VAL=$(calc_color "$PRIMARY_COLOR" "darken" 12)
    HOVER_ORANGE_BG_VAL=$(rgb_to_hex $HOVER_ORANGE_BG_VAL)
else
    HOVER_MUTED_BG_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 12)
    HOVER_MUTED_BG_VAL=$(rgb_to_hex $HOVER_MUTED_BG_VAL)
    HOVER_TEAL_BG_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 16)
    HOVER_TEAL_BG_VAL=$(rgb_to_hex $HOVER_TEAL_BG_VAL)
    HOVER_GREEN_BG_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 14)
    HOVER_GREEN_BG_VAL=$(rgb_to_hex $HOVER_GREEN_BG_VAL)
    HOVER_GOLD_BG_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 18)
    HOVER_GOLD_BG_VAL=$(rgb_to_hex $HOVER_GOLD_BG_VAL)
    HOVER_ORANGE_BG_VAL=$(calc_color "$PRIMARY_COLOR" "lighten" 20)
    HOVER_ORANGE_BG_VAL=$(rgb_to_hex $HOVER_ORANGE_BG_VAL)
fi

# ── Replace all placeholders ──────────────────────────────────────────────────
sed -i "s/__CALC_SURFACE__/$SURFACE_VAL/g"                     "$PALETTE_NIX"
sed -i "s/__CALC_OVERLAY__/$OVERLAY_VAL/g"                     "$PALETTE_NIX"
sed -i "s/__CALC_HIGHLIGHT_LOW__/$HIGHLIGHT_LOW_VAL/g"         "$PALETTE_NIX"
sed -i "s/__CALC_HIGHLIGHT_MED__/$HIGHLIGHT_MED_VAL/g"         "$PALETTE_NIX"
sed -i "s/__CALC_HIGHLIGHT_HIGH__/$HIGHLIGHT_HIGH_VAL/g"       "$PALETTE_NIX"
sed -i "s/__CALC_MUTED__/$MUTED_VAL/g"                         "$PALETTE_NIX"
sed -i "s/__CALC_SUBTLE__/$SUBTLE_VAL/g"                       "$PALETTE_NIX"
sed -i "s/__CALC_TEXT__/$TEXT_VAL/g"                           "$PALETTE_NIX"
sed -i "s/__CALC_ROSE__/$ROSE_VAL/g"                           "$PALETTE_NIX"
sed -i "s/__CALC_GOLD__/$GOLD_VAL/g"                           "$PALETTE_NIX"
sed -i "s/__CALC_PINE__/$PINE_VAL/g"                           "$PALETTE_NIX"
sed -i "s/__CALC_FOAM__/$FOAM_VAL/g"                           "$PALETTE_NIX"
sed -i "s/__CALC_CRITICAL__/$CRITICAL_VAL/g"                   "$PALETTE_NIX"
sed -i "s/__CALC_WARNING__/$WARNING_VAL/g"                     "$PALETTE_NIX"
sed -i "s/__CALC_CAUTION__/$CAUTION_VAL/g"                     "$PALETTE_NIX"
sed -i "s/__CALC_MUTED_ICON__/$MUTED_ICON_VAL/g"               "$PALETTE_NIX"
sed -i "s/__CALC_INACTIVE_BORDER__/$INACTIVE_BORDER_VAL/g"     "$PALETTE_NIX"
sed -i "s/__CALC_SHADOW__/$SHADOW_VAL/g"                       "$PALETTE_NIX"
sed -i "s/__CALC_SHADOW_RGB__/$SHADOW_RGB_VAL/g"               "$PALETTE_NIX"
sed -i "s/__CALC_WB_BASE__/$WB_BASE_VAL/g"                     "$PALETTE_NIX"
sed -i "s/__CALC_WB_SURFACE__/$WB_SURFACE_VAL/g"               "$PALETTE_NIX"
sed -i "s/__CALC_WB_OVERLAY__/$WB_OVERLAY_VAL/g"               "$PALETTE_NIX"
sed -i "s/__CALC_GRAD_BASE_HI__/$GRAD_BASE_HI_VAL/g"           "$PALETTE_NIX"
sed -i "s/__CALC_GRAD_BASE_LO__/$GRAD_BASE_LO_VAL/g"           "$PALETTE_NIX"
sed -i "s/__CALC_GRAD_SURFACE_HI__/$GRAD_SURFACE_HI_VAL/g"     "$PALETTE_NIX"
sed -i "s/__CALC_GRAD_SURFACE_LO__/$GRAD_SURFACE_LO_VAL/g"     "$PALETTE_NIX"
sed -i "s/__CALC_GRAD_OVERLAY_HI__/$GRAD_OVERLAY_HI_VAL/g"     "$PALETTE_NIX"
sed -i "s/__CALC_GRAD_OVERLAY_LO__/$GRAD_OVERLAY_LO_VAL/g"     "$PALETTE_NIX"
sed -i "s/__CALC_BORDER_ACCENT_RGB__/$BORDER_ACCENT_RGB_VAL/g" "$PALETTE_NIX"
sed -i "s/__CALC_BORDER_IRIS_RGB__/$BORDER_IRIS_RGB_VAL/g"     "$PALETTE_NIX"
sed -i "s/__CALC_BORDER_ACCENT__/$BORDER_ACCENT_VAL/g"         "$PALETTE_NIX"
sed -i "s/__CALC_ACCENT_SECONDARY__/$ACCENT_SECONDARY_VAL/g"   "$PALETTE_NIX"
sed -i "s/__CALC_BATTERY_CRIT__/$BATTERY_CRIT_VAL/g"           "$PALETTE_NIX"
sed -i "s/__CALC_BATTERY_LOW__/$BATTERY_LOW_VAL/g"             "$PALETTE_NIX"
sed -i "s/__CALC_BATTERY_MED__/$BATTERY_MED_VAL/g"             "$PALETTE_NIX"
sed -i "s/__CALC_BATTERY_HIGH__/$BATTERY_HIGH_VAL/g"           "$PALETTE_NIX"
sed -i "s/__CALC_BATTERY_FULL__/$BATTERY_FULL_VAL/g"           "$PALETTE_NIX"
sed -i "s/__CALC_TINT_PINE_DARK__/$TINT_PINE_DARK_VAL/g"       "$PALETTE_NIX"
sed -i "s/__CALC_TINT_PINE_MID__/$TINT_PINE_MID_VAL/g"         "$PALETTE_NIX"
sed -i "s/__CALC_TINT_CRITICAL_BG__/$TINT_CRITICAL_BG_VAL/g"   "$PALETTE_NIX"
sed -i "s/__CALC_HOVER_MUTED_BG__/$HOVER_MUTED_BG_VAL/g"       "$PALETTE_NIX"
sed -i "s/__CALC_HOVER_TEAL_BG__/$HOVER_TEAL_BG_VAL/g"         "$PALETTE_NIX"
sed -i "s/__CALC_HOVER_GREEN_BG__/$HOVER_GREEN_BG_VAL/g"        "$PALETTE_NIX"
sed -i "s/__CALC_HOVER_GOLD_BG__/$HOVER_GOLD_BG_VAL/g"         "$PALETTE_NIX"
sed -i "s/__CALC_HOVER_ORANGE_BG__/$HOVER_ORANGE_BG_VAL/g"     "$PALETTE_NIX"

echo "✅ Palette math complete. Placeholders replaced."

# -----------------------------------------------------------------------------
# Step 3: Generate Shell Script
# -----------------------------------------------------------------------------
cat <<EOF > "$PALETTE_SH"
#!/usr/bin/env bash
# $THEME_NAME — generated palette for waybar scripts

# ── Base colors ───────────────────────────────────────────────
BASE="$PRIMARY_COLOR"
SURFACE="$SURFACE_VAL"
OVERLAY="$OVERLAY_VAL"
MUTED="$MUTED_VAL"
SUBTLE="$SUBTLE_VAL"
TEXT="$TEXT_VAL"

# ── Accent spectrum (from secondary) ──────────────────────────
LOVE="$SECONDARY_COLOR"
ROSE="$ROSE_VAL"
GOLD="$GOLD_VAL"
PINE="$PINE_VAL"
FOAM="$FOAM_VAL"
IRIS="$IRIS_COLOR"

# ── Highlight tiers ───────────────────────────────────────────
HIGHLIGHT_LOW="$HIGHLIGHT_LOW_VAL"
HIGHLIGHT_MED="$HIGHLIGHT_MED_VAL"
HIGHLIGHT_HIGH="$HIGHLIGHT_HIGH_VAL"

# ── Waybar bar tiers ──────────────────────────────────────────
WB_BASE="$WB_BASE_VAL"
WB_SURFACE="$WB_SURFACE_VAL"
WB_OVERLAY="$WB_OVERLAY_VAL"

# ── Text roles ────────────────────────────────────────────────
TEXT_PRIMARY="\$TEXT"
TEXT_SECONDARY="\$SUBTLE"
INK="\$TEXT_PRIMARY"

# ── Accent roles ──────────────────────────────────────────────
ACCENT_PRIMARY="$IRIS_COLOR"
ACCENT_SECONDARY="$ACCENT_SECONDARY_VAL"
BORDER_ACCENT="$BORDER_ACCENT_VAL"

# ── Battery semantic colors ───────────────────────────────────
BATTERY_CRIT="$BATTERY_CRIT_VAL"
BATTERY_LOW="$BATTERY_LOW_VAL"
BATTERY_MED="$BATTERY_MED_VAL"
BATTERY_HIGH="$BATTERY_HIGH_VAL"
BATTERY_FULL="$BATTERY_FULL_VAL"

# ── Status roles ──────────────────────────────────────────────
WARN="\$GOLD"
ERROR="\$LOVE"
SUCCESS="\$FOAM"
INFO="\$IRIS"

# ── Weather semantic colors (glyph-only usage) ────────────────
WX_SUN_LIGHT="\$GOLD"
WX_SUN_MEDIUM="\$ROSE"
WX_SUN_HEAVY="\$LOVE"

WX_RAIN_LIGHT="\$FOAM"
WX_RAIN_MEDIUM="\$ACCENT_SECONDARY"
WX_RAIN_HEAVY="\$PINE"

WX_CLOUD_LIGHT="\$TEXT_SECONDARY"
WX_CLOUD_MEDIUM="\$SUBTLE"
WX_CLOUD_HEAVY="\$MUTED"

WX_SNOW_LIGHT="\$TEXT_PRIMARY"
WX_SNOW_HEAVY="\$FOAM"

WX_FOG_LIGHT="\$SUBTLE"
WX_FOG_HEAVY="\$MUTED"

WX_STORM_HEAVY="\$LOVE"
EOF

chmod +x "$PALETTE_SH"
echo "✅ Created $PALETTE_SH"

# -----------------------------------------------------------------------------
# Step 4: Run Harmonizer (Structural Sync)
# -----------------------------------------------------------------------------
if [[ -f "$HARMONIZER" ]]; then
    echo "🔄 Running Harmonizer to ensure structural consistency..."
    "$HARMONIZER"
else
    echo "⚠️  Warning: Harmonizer script not found at $HARMONIZER. Skipping sync."
fi

# -----------------------------------------------------------------------------
# Final Output
# -----------------------------------------------------------------------------
echo "✨ Done! Theme '$THEME_NAME' is ready."
echo "   Location: $THEME_DIR"
echo "   Slug: $SLUG"
echo "   Mode: $MODE"
echo ""
echo "   Inputs:"
echo "     Primary   (base):  $PRIMARY_COLOR"
echo "     Love      (warm):  $SECONDARY_COLOR"
echo "     Pine      (green): $PINE_COLOR"
echo "     Iris      (accent):$IRIS_COLOR"
echo "     Gold      (warm):  $GOLD_COLOR"
echo ""
echo "   Bar colors: WB_BASE=$WB_BASE_VAL  WB_SURFACE=$WB_SURFACE_VAL  WB_OVERLAY=$WB_OVERLAY_VAL"
echo ""
echo "   Next steps:"
echo "   1. Review $PALETTE_NIX"
echo "   2. Rebuild: nrs"
echo "   3. Activate: set-theme $SLUG"
