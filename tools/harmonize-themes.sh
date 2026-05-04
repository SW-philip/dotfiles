#!/usr/bin/env bash

set -euo pipefail

THEME_ROOT="$HOME/nixos/themes"
MASTER_FILE="$THEME_ROOT/Rose-Pine/main/palette-main.nix"

if [[ ! -f "$MASTER_FILE" ]]; then
    echo "❌ Error: Master file not found at $MASTER_FILE"
    exit 1
fi

echo "--- 🔍 Step 1: Building Global Attribute List from Master ---"

# Extract all attribute names (keys)
GLOBAL_LIST=$(grep -E '^[[:space:]]*[A-Z0-9_]+\s*=' "$MASTER_FILE" | \
              grep -v '^[[:space:]]*#' | \
              sed -E 's/^[[:space:]]*([A-Z0-9_]+)\s*=.*/\1/' | \
              sort -u)

COUNT=$(echo "$GLOBAL_LIST" | wc -l)
echo "Syncing $COUNT attributes across all themes."
echo "------------------------------------------------"

# -----------------------------------------------------------------------------
# Math Engine (Copied from gen-lix-theme.sh)
# -----------------------------------------------------------------------------
hex_to_rgb() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    echo "$r $g $b"
}

rgb_to_hex() {
    printf "#%02x%02x%02x" "$1" "$2" "$3"
}

calc_color() {
    local hex=$1
    local op=$2
    local amt=$3
    read -r r g b <<< "$(hex_to_rgb "$hex")"

    # CRITICAL: Ensure awk output has NO trailing newline
    awk -v r="$r" -v g="$g" -v b="$b" -v op="$op" -v amt="$amt" 'BEGIN {
        r_n = r/255; g_n = g/255; b_n = b/255
        max = (r_n>g_n && r_n>b_n) ? r_n : ((g_n>b_n) ? g_n : b_n)
        min = (r_n<g_n && r_n<b_n) ? r_n : ((g_n<b_n) ? g_n : b_n)
        l = (max + min) / 2
        if (max == min) { s = 0; h_hue = 0 }
        else {
            d = max - min
            s = (l > 0.5) ? d / (2 - max - min) : d / (max + min)
            if (max == r_n) h_hue = (g_n - b_n) / d + (g_n < b_n ? 6 : 0)
            else if (max == g_n) h_hue = (b_n - r_n) / d + 2
            else h_hue = (r_n - g_n) / d + 4
            h_hue /= 6
        }
        if (op == "lighten") l = l + (amt / 100)
        else if (op == "darken") l = l - (amt / 100)
        else if (op == "desaturate") s = s * (1 - (amt / 100))
        else if (op == "shift_hue") { h_hue = (h_hue + (amt / 360)) % 1; if (h_hue < 0) h_hue += 1 }

        if (l > 1) l = 1; if (l < 0) l = 0
        if (s > 1) s = 1; if (s < 0) s = 0

        if (s == 0) { r_out = g_out = b_out = l }
        else {
            q = (l < 0.5) ? l * (1 + s) : l + s - l * s
            p = 2 * l - q
            t1 = h_hue + 1/3; if (t1 < 0) t1 += 1; if (t1 > 1) t1 -= 1
            if (t1 < 1/6) r_out = p + (q - p) * 6 * t1
            else if (t1 < 1/2) r_out = q
            else if (t1 < 2/3) r_out = p + (q - p) * (2/3 - t1) * 6
            else r_out = p

            t2 = h_hue; if (t2 < 0) t2 += 1; if (t2 > 1) t2 -= 1
            if (t2 < 1/6) g_out = p + (q - p) * 6 * t2
            else if (t2 < 1/2) g_out = q
            else if (t2 < 2/3) g_out = p + (q - p) * (2/3 - t2) * 6
            else g_out = p

            t3 = h_hue - 1/3; if (t3 < 0) t3 += 1; if (t3 > 1) t3 -= 1
            if (t3 < 1/6) b_out = p + (q - p) * 6 * t3
            else if (t3 < 1/2) b_out = q
            else if (t3 < 2/3) b_out = p + (q - p) * (2/3 - t3) * 6
            else b_out = p
        }
        printf "%d %d %d", int(r_out*255+0.5), int(g_out*255+0.5), int(b_out*255+0.5)
    }'
}

# -----------------------------------------------------------------------------
# Step 2: Process Themes
# -----------------------------------------------------------------------------
find "$THEME_ROOT" -name "*.nix" -not -path "*/themesbk/*" | while read -r theme_file; do
    [[ "$theme_file" == "$MASTER_FILE" ]] && continue

    rel_path="${theme_file#$THEME_ROOT/}"
    echo "Processing: $rel_path"

    MODIFIED=0
    MISSING_LINES=""

    # Extract existing BASE and LOVE colors from the CURRENT theme
    CURRENT_BASE=$(grep -E '^[[:space:]]*BASE\s*=' "$theme_file" | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -n1)
    CURRENT_LOVE=$(grep -E '^[[:space:]]*LOVE\s*=' "$theme_file" | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -n1)

    # Fallback
    [[ -z "$CURRENT_BASE" ]] && CURRENT_BASE="#d0c8c4"
    [[ -z "$CURRENT_LOVE" ]] && CURRENT_LOVE="#a86077"

    # Determine theme mode (same brightness threshold as gen-lix-theme.sh)
    read -r _br _bg _bb <<< "$(hex_to_rgb "$CURRENT_BASE")"
    _brightness=$(( (_br * 299 + _bg * 587 + _bb * 114) / 1000 ))
    THEME_MODE="dark"
    (( _brightness >= 128 )) && THEME_MODE="light"

    while read -r key; do
        if ! grep -qE "^[[:space:]]*$key\s*=" "$theme_file"; then
            master_line=$(grep -E "^[[:space:]]*$key\s*=" "$MASTER_FILE" | head -n1)
            master_val=$(echo "$master_line" | sed -E 's/.*=\s*"([^"]+)".*/\1/')

            NEW_VAL=""
            CALCULATED=false

            case "$key" in
                SURFACE)
                    NEW_VAL=$(calc_color "$CURRENT_BASE" "lighten" 10) ;;
                OVERLAY)
                    NEW_VAL=$(calc_color "$CURRENT_BASE" "lighten" 20) ;;
                HIGHLIGHT_LOW)
                    NEW_VAL=$(calc_color "$CURRENT_BASE" "lighten" 5) ;;
                HIGHLIGHT_MED)
                    NEW_VAL=$(calc_color "$CURRENT_BASE" "lighten" 12) ;;
                HIGHLIGHT_HIGH)
                    NEW_VAL=$(calc_color "$CURRENT_BASE" "lighten" 25) ;;
                MUTED)
                    TEMP=$(calc_color "$CURRENT_BASE" "desaturate" 40)
                    TEMP_HEX=$(rgb_to_hex ${TEMP})
                    NEW_VAL=$(calc_color "$TEMP_HEX" "lighten" 30) ;;
                SUBTLE)
                    TEMP=$(calc_color "$CURRENT_BASE" "desaturate" 50)
                    TEMP_HEX=$(rgb_to_hex ${TEMP})
                    NEW_VAL=$(calc_color "$TEMP_HEX" "lighten" 40) ;;
                ROSE)
                    NEW_VAL=$(calc_color "$CURRENT_LOVE" "shift_hue" -20) ;;
                GOLD)
                    NEW_VAL=$(calc_color "$CURRENT_LOVE" "shift_hue" 40) ;;
                PINE)
                    NEW_VAL=$(calc_color "$CURRENT_LOVE" "darken" 60) ;;
                FOAM)
                    TEMP=$(calc_color "$CURRENT_LOVE" "desaturate" 30)
                    TEMP_HEX=$(rgb_to_hex ${TEMP})
                    NEW_VAL=$(calc_color "$TEMP_HEX" "darken" 15) ;;
                IRIS)
                    NEW_VAL=$(calc_color "$CURRENT_LOVE" "shift_hue" 20) ;;
                CRITICAL)
                    NEW_VAL=$(calc_color "$CURRENT_LOVE" "shift_hue" -10) ;;
                WARNING)
                    NEW_VAL=$(calc_color "$CURRENT_LOVE" "shift_hue" 35) ;;
                CAUTION)
                    NEW_VAL=$(calc_color "$CURRENT_LOVE" "lighten" 20) ;;
                MUTED_ICON)
                    TEMP=$(calc_color "$CURRENT_BASE" "desaturate" 20)
                    TEMP_HEX=$(rgb_to_hex ${TEMP})
                    NEW_VAL=$(calc_color "$TEMP_HEX" "lighten" 15) ;;
                TINT_PINE_DARK)
                    PINE_TEMP=$(calc_color "$CURRENT_LOVE" "darken" 60)
                    PINE_HEX=$(rgb_to_hex ${PINE_TEMP})
                    if [[ "$THEME_MODE" == "dark" ]]; then
                        NEW_VAL=$(calc_color "$PINE_HEX" "darken" 35)
                    else
                        NEW_VAL=$(calc_color "$PINE_HEX" "lighten" 40)
                    fi ;;
                TINT_PINE_MID)
                    PINE_TEMP=$(calc_color "$CURRENT_LOVE" "darken" 60)
                    PINE_HEX=$(rgb_to_hex ${PINE_TEMP})
                    if [[ "$THEME_MODE" == "dark" ]]; then
                        NEW_VAL=$(calc_color "$PINE_HEX" "darken" 32)
                    else
                        NEW_VAL=$(calc_color "$PINE_HEX" "lighten" 45)
                    fi ;;
                TINT_CRITICAL_BG)
                    CRIT_TEMP=$(calc_color "$CURRENT_LOVE" "shift_hue" -10)
                    CRIT_HEX=$(rgb_to_hex ${CRIT_TEMP})
                    if [[ "$THEME_MODE" == "dark" ]]; then
                        NEW_VAL=$(calc_color "$CRIT_HEX" "darken" 55)
                    else
                        NEW_VAL=$(calc_color "$CRIT_HEX" "lighten" 40)
                    fi ;;
                HOVER_MUTED_BG)
                    if [[ "$THEME_MODE" == "dark" ]]; then
                        NEW_VAL=$(calc_color "$CURRENT_BASE" "darken" 3)
                    else
                        NEW_VAL=$(calc_color "$CURRENT_BASE" "lighten" 12)
                    fi ;;
                HOVER_TEAL_BG)
                    if [[ "$THEME_MODE" == "dark" ]]; then
                        NEW_VAL=$(calc_color "$CURRENT_BASE" "darken" 8)
                    else
                        NEW_VAL=$(calc_color "$CURRENT_BASE" "lighten" 16)
                    fi ;;
                HOVER_GREEN_BG)
                    if [[ "$THEME_MODE" == "dark" ]]; then
                        NEW_VAL=$(calc_color "$CURRENT_BASE" "darken" 10)
                    else
                        NEW_VAL=$(calc_color "$CURRENT_BASE" "lighten" 14)
                    fi ;;
                HOVER_GOLD_BG)
                    if [[ "$THEME_MODE" == "dark" ]]; then
                        NEW_VAL=$(calc_color "$CURRENT_BASE" "darken" 7)
                    else
                        NEW_VAL=$(calc_color "$CURRENT_BASE" "lighten" 18)
                    fi ;;
                HOVER_ORANGE_BG)
                    if [[ "$THEME_MODE" == "dark" ]]; then
                        NEW_VAL=$(calc_color "$CURRENT_BASE" "darken" 12)
                    else
                        NEW_VAL=$(calc_color "$CURRENT_BASE" "lighten" 20)
                    fi ;;
                TERTIARY_DARK)
                    TERT=$(grep -E '^[[:space:]]*TERTIARY\s*=' "$theme_file" | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -n1)
                    [[ -z "$TERT" ]] && TERT="$CURRENT_LOVE"
                    NEW_VAL=$(calc_color "$TERT" "darken" 20) ;;
                TERTIARY_LIGHT)
                    TERT=$(grep -E '^[[:space:]]*TERTIARY\s*=' "$theme_file" | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -n1)
                    [[ -z "$TERT" ]] && TERT="$CURRENT_LOVE"
                    NEW_VAL=$(calc_color "$TERT" "lighten" 20) ;;
                *)
                    NEW_VAL="$master_val"
                    ;;
            esac

            # CRITICAL FIX: Strip ANY newlines or whitespace from NEW_VAL
            NEW_VAL="${NEW_VAL//$'\n'/}"
            NEW_VAL="${NEW_VAL//$'\r'/}"
            NEW_VAL="${NEW_VAL// /}" # Remove any accidental spaces

            # Construct the line
            clean_line="  $key = \"$NEW_VAL\";"
            MISSING_LINES+="$clean_line"$'\n'
            MODIFIED=1
        fi
    done <<< "$GLOBAL_LIST"

    if [[ $MODIFIED -eq 1 ]]; then
        echo "   🩹 Adding $(( $(echo "$MISSING_LINES" | wc -l) )) missing attributes..."

        tmp_file=$(mktemp)
        last_brace_line=$(grep -n '^}' "$theme_file" | tail -n1 | cut -d: -f1)

        if [[ -z "$last_brace_line" ]]; then
            echo "      ⚠️ Warning: No closing brace found. Appending."
            echo -e "$MISSING_LINES" >> "$theme_file"
        else
            head -n $((last_brace_line - 1)) "$theme_file" > "$tmp_file"
            # Use printf to avoid adding extra newlines
            printf '%s' "$MISSING_LINES" >> "$tmp_file"
            tail -n +$last_brace_line "$theme_file" >> "$tmp_file"
            mv "$tmp_file" "$theme_file"
        fi
        echo "   ✅ Updated with dynamic colors."
    else
        echo "   ✅ Already complete."
    fi
done

echo "------------------------------------------------"
echo "Done. All themes now have dynamic, calculated colors."
