import sys

def hex_to_rgb(hex_str):
    hex_str = hex_str.lstrip('#')
    return [int(hex_str[i:i+2], 16) for i in (0, 2, 4)]

def rgb_to_hex(rgb):
    return "#{:02x}{:02x}{:02x}".format(*(max(0, min(255, int(c))) for c in rgb))

def adjust(hex_str, brightness):
    rgb = hex_to_rgb(hex_str)
    return rgb_to_hex([c + (brightness * 255) for c in rgb])

def blend(hex_a, hex_b, t):
    """Linear interpolate between two hex colors. t=0 → a, t=1 → b."""
    a = hex_to_rgb(hex_a)
    b = hex_to_rgb(hex_b)
    return rgb_to_hex([a[i] + (b[i] - a[i]) * t for i in range(3)])

def luminance(hex_str):
    r, g, b = hex_to_rgb(hex_str)
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255

def contrast_ratio(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

def color_at_contrast(bg, target_ratio, toward):
    """Binary-search for the color between bg and `toward` that hits target_ratio.
    Returns `toward` if the target is unachievable (bg already too light/dark)."""
    if contrast_ratio(toward, bg) <= target_ratio:
        return toward
    lo, hi = 0.0, 1.0
    for _ in range(24):
        t = (lo + hi) / 2
        if contrast_ratio(blend(bg, toward, t), bg) < target_ratio:
            lo = t
        else:
            hi = t
    return blend(bg, toward, (lo + hi) / 2)

def clamp_lum(hex_color, max_lum, toward):
    """Blend toward black/white until luminance is within max_lum.
    toward='#000000' darkens; toward='#ffffff' lightens."""
    lum = luminance(hex_color)
    if toward == '#000000' and lum <= max_lum:
        return hex_color
    if toward == '#ffffff' and lum >= max_lum:
        return hex_color
    lo, hi = 0.0, 1.0
    for _ in range(24):
        t = (lo + hi) / 2
        cand_lum = luminance(blend(hex_color, toward, t))
        if toward == '#000000':
            lo, hi = (t, hi) if cand_lum > max_lum else (lo, t)
        else:
            lo, hi = (t, hi) if cand_lum < max_lum else (lo, t)
    return blend(hex_color, toward, (lo + hi) / 2)

def is_dark(hex_str):
    return luminance(hex_str) < 0.4

if len(sys.argv) < 3:
    print("Usage: python generate-palette.py <BASE_HEX> <LOVE_HEX>")
    sys.exit(1)

base = sys.argv[1]
love = sys.argv[2]
if not base.startswith('#'): base = '#' + base
if not love.startswith('#'): love = '#' + love

dark = is_dark(base)
text_anchor = '#ffffff' if dark else '#1a1a1a'
text = '#ffffff' if dark else '#1a1a1a'

surface = adjust(base, 0.05)
overlay = adjust(base, 0.10)

# Widget background tiers — clamped to a max luminance so icon/text contrast
# is always achievable regardless of where the palette base sits.
# Thresholds calibrated to Rosé Pine Moon's actual WB values (the reference dark theme).
#   WB_BASE    lum ~0.13  → darkest pill (connectivity, storage, toggles)
#   WB_SURFACE lum ~0.15  → standard pill (weather, volume, mpris)
#   WB_OVERLAY lum ~0.18  → elevated pill (clock, battery, system-stats)
if dark:
    wb_base    = clamp_lum(base,    0.13, '#000000')
    wb_surface = clamp_lum(surface, 0.15, '#000000')
    wb_overlay = clamp_lum(overlay, 0.18, '#000000')
else:
    wb_base    = clamp_lum(base,    0.87, '#ffffff')
    wb_surface = clamp_lum(surface, 0.85, '#ffffff')
    wb_overlay = clamp_lum(overlay, 0.82, '#ffffff')

# Gradient depth anchors — subtle depth within each clamped tier (±2% brightness)
grad_surface_hi = adjust(wb_surface,  0.02)
grad_surface_lo = adjust(wb_surface, -0.02)
grad_overlay_hi = adjust(wb_overlay,  0.02)
grad_overlay_lo = adjust(wb_overlay, -0.02)
grad_base_hi    = adjust(wb_base,     0.02)
grad_base_lo    = adjust(wb_base,    -0.02)

# Icon/text tiers — contrast-solved against their actual resting background.
# Calibrated to match Rosé Pine Moon's legibility profile:
#   MUTED_ICON ~4:1   (most icons at rest, on WB_SURFACE)
#   SUBTLE     ~3:1   (paused/secondary states — dimmer than MUTED_ICON)
#   MUTED      ~3:1   (inactive workspaces on WB_BASE, muted volume)
#   TEXT_SECONDARY ~4.5:1 (descriptive labels, between MUTED_ICON and TEXT)
muted_icon     = color_at_contrast(wb_surface, 4.0, text_anchor)
subtle         = color_at_contrast(wb_surface, 3.0, text_anchor)
muted          = color_at_contrast(wb_base,    3.0, text_anchor)
text_secondary = color_at_contrast(wb_surface, 4.5, text_anchor)

# Structural shadow — strong for dark themes, moderate for light
icon_shadow = "0 1px 2px rgba(0,0,0,0.80)" if dark else "0 1px 2px rgba(0,0,0,0.40)"
shadow_a_outer = "0.50" if dark else "0.10"
shadow_a_drop  = "0.55" if dark else "0.07"
shadow_a_hover = "0.65" if dark else "0.10"
inset_top_a    = "0.08" if dark else "0.50"
inset_bot_a    = "0.30" if dark else "0.08"
border_top_a   = "0.07" if dark else "0.65"
shadow_rgb     = "0,0,0" if dark else ",".join(str(c) for c in hex_to_rgb(adjust(base, -0.30)))

# Hover backgrounds — darkened from base so bright state-colored text pops.
if dark:
    hover_muted_bg  = adjust(base, -0.03)
    hover_teal_bg   = adjust(base, -0.08)
    hover_green_bg  = adjust(base, -0.10)
    hover_gold_bg   = adjust(base, -0.07)
    hover_orange_bg = adjust(base, -0.12)
    tint_pine_dark  = adjust(base, -0.06)
    tint_pine_mid   = adjust(base, -0.04)
    tint_critical   = adjust(base, -0.08)
else:
    hover_muted_bg  = adjust(base, 0.12)
    hover_teal_bg   = adjust(base, 0.16)
    hover_green_bg  = adjust(base, 0.14)
    hover_gold_bg   = adjust(base, 0.18)
    hover_orange_bg = adjust(base, 0.20)
    tint_pine_dark  = adjust(base, 0.10)
    tint_pine_mid   = adjust(base, 0.12)
    tint_critical   = adjust(base, 0.08)

base_rgb = ",".join(str(c) for c in hex_to_rgb(base))
love_rgb = ",".join(str(c) for c in hex_to_rgb(love))

print(f"""{{
  # ── Base ──────────────────────────────────────────────────────
  BASE           = "{base}";
  SURFACE        = "{surface}";
  OVERLAY        = "{overlay}";
  HIGHLIGHT_LOW  = "{adjust(base, 0.03)}";
  HIGHLIGHT_MED  = "{adjust(base, 0.07)}";
  HIGHLIGHT_HIGH = "{adjust(base, 0.12)}";

  # ── Text & accents ─────────────────────────────────────────────
  # TODO: replace fallbacks with theme-appropriate colors
  MUTED  = "{muted}";
  SUBTLE = "{subtle}";
  TEXT   = "{text}";
  LOVE   = "{love}";
  ROSE   = "#ebbcba";   # TODO
  GOLD   = "#f6c177";   # TODO
  PINE   = "#31748f";   # TODO
  FOAM   = "#9ccfd8";   # TODO
  IRIS   = "#c4a7e7";   # TODO

  # ── Extended — named system-state colors ──────────────────────
  # TODO: tune semantic state colors to fit this palette
  CRITICAL   = "{text}";
  WARNING    = "{text}";
  CAUTION    = "{text}";
  MUTED_ICON = "{muted_icon}";

  # ── Structural ────────────────────────────────────────────────
  INACTIVE_BORDER = "{adjust(base, 0.15)}";
  SHADOW          = "{adjust(base, -0.30)}";

  # ── Waybar module background tiers ───────────────────────────
  WB_BASE    = "{wb_base}";
  WB_SURFACE = "{wb_surface}";
  WB_OVERLAY = "{wb_overlay}";

  # ── Gradient depth anchors ────────────────────────────────────
  GRAD_SURFACE_HI = "{grad_surface_hi}";
  GRAD_SURFACE_LO = "{grad_surface_lo}";
  GRAD_OVERLAY_HI = "{grad_overlay_hi}";
  GRAD_OVERLAY_LO = "{grad_overlay_lo}";
  GRAD_BASE_HI    = "{grad_base_hi}";
  GRAD_BASE_LO    = "{grad_base_lo}";

  # ── Accent border tints ───────────────────────────────────────
  # TODO: pick a border accent that suits the palette
  BORDER_ACCENT_RGB = "{love_rgb}";
  BORDER_IRIS_RGB   = "{love_rgb}";   # TODO: replace with iris-tinted RGB

  # ── Derived tinted backgrounds ────────────────────────────────
  # These are used by battery/network hover states and the thermal gradient.
  # Each must be dark enough that light text (FOAM, CAUTION, etc.) is readable on top.
  TINT_PINE_DARK   = "{tint_pine_dark}";
  TINT_PINE_MID    = "{tint_pine_mid}";
  TINT_CRITICAL_BG = "{tint_critical}";

  # ── State-tinted hover backgrounds ────────────────────────────
  # IMPORTANT: These MUST contrast with the text colors used in each state.
  # Dark themes: use dark tinted values. Light themes: use pale washed values.
  # Never set to #ffffff — that makes text invisible in thermal gradient states.
  HOVER_MUTED_BG  = "{hover_muted_bg}";
  HOVER_TEAL_BG   = "{hover_teal_bg}";
  HOVER_GREEN_BG  = "{hover_green_bg}";
  HOVER_GOLD_BG   = "{hover_gold_bg}";   # vol-60–65: must contrast with CAUTION text
  HOVER_ORANGE_BG = "{hover_orange_bg}";  # vol-70–75: must contrast with WARNING text

  # ── Bar typography ───────────────────────────────────────────
  FONT_SIZE_BAR = "12px";
  ICON_SHADOW   = "{icon_shadow}";

  # ── Box-shadow composition ───────────────────────────────────
  SHADOW_RGB     = "{shadow_rgb}";
  SHADOW_A_OUTER = "{shadow_a_outer}";
  SHADOW_A_DROP  = "{shadow_a_drop}";
  SHADOW_A_HOVER = "{shadow_a_hover}";
  INSET_TOP_A    = "{inset_top_a}";
  INSET_BOT_A    = "{inset_bot_a}";
  BORDER_TOP_A   = "{border_top_a}";

  # ── Battery ───────────────────────────────────────────────────
  # TODO: tune to palette semantics
  BATTERY_FULL = "#31748f";
  BATTERY_HIGH = "#9ccfd8";
  BATTERY_MED  = "#ebbcba";
  BATTERY_LOW  = "#f6c177";
  BATTERY_CRIT = "#eb6f92";

  # ── Named accent roles ────────────────────────────────────────
  BORDER_ACCENT    = "{love}";   # TODO
  ACCENT_PRIMARY   = "{love}";   # TODO
  TEXT_PRIMARY     = "{text}";
  TEXT_SECONDARY   = "{text_secondary}";
  ACCENT_SECONDARY = "#9ccfd8";  # TODO
}}""")
