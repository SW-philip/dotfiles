# Lilac-Juniper — custom light variant, nix mirror of palette-lilac-juniper.sh
# Cool lavender-white base; juniper-patina blue (PINE) + forest sage (FOAM) +
# lilac (IRIS) + amber (GOLD). All accents are one pastel step off Rosé Pine Dawn.
# Keep in sync with palette-lilac-juniper.sh when updating colors.
{
  # ── Base ──────────────────────────────────────────────────────
  BASE           = "#f4f0fc";
  SURFACE        = "#ede8f8";
  OVERLAY        = "#e2daf0";
  HIGHLIGHT_LOW  = "#eee8f8";
  HIGHLIGHT_MED  = "#dbd4ec";
  HIGHLIGHT_HIGH = "#c8c0e0";

  # ── Text & accents ────────────────────────────────────────────
  MUTED  = "#9088b8";   # quiet lavender-purple (light = low contrast on light bg)
  SUBTLE = "#7a72a0";   # readable lavender-purple
  TEXT   = "#3e3868";   # deep indigo-purple
  LOVE   = "#b06080";   # dusty berry-rose
  ROSE   = "#c87880";   # dusty rose
  GOLD   = "#c87820";   # warm amber (vs Dawn's orange-gold)
  PINE   = "#507aaa";   # juniper-patina periwinkle-slate (the frosted berry)
  FOAM   = "#5a8a6a";   # forest sage green (the juniper branch)
  IRIS   = "#9070c0";   # lilac — cooler, slightly more saturated than Dawn

  # ── Extended — named system-state colors ──────────────────────
  CRITICAL   = "#b06080";   # LOVE
  WARNING    = "#c87820";   # GOLD/amber
  CAUTION    = "#7a9420";   # muted yellow-green, readable on light bg
  MUTED_ICON = "#706a88";   # darkened for contrast on lavender-grey surfaces

  # ── Semantic aliases ──────────────────────────────────────────
  TEXT_PRIMARY   = "#3e3868";
  TEXT_SECONDARY = "#7a72a0";
  ACCENT_PRIMARY   = "#9070c0";   # lilac
  ACCENT_SECONDARY = "#507aaa";   # juniper patina

  # ── Battery ───────────────────────────────────────────────────
  BATTERY_FULL = "#507aaa";
  BATTERY_HIGH = "#5a8a6a";
  BATTERY_MED  = "#c87880";
  BATTERY_LOW  = "#c87820";
  BATTERY_CRIT = "#b06080";

  # ── Waybar module background tiers ───────────────────────────
  # Lavender-grey slate — clearly grey-purple (not white) on the lavender-white desktop.
  # Depth order matches dark mode: OVERLAY = most elevated.
  WB_BASE    = "#ccc8dc";   # tray, pill groups — light lavender-slate
  WB_SURFACE = "#c4c0d4";   # weather, volume, mpris, cpu_temp — mid lavender-slate
  WB_OVERLAY = "#bab6cc";   # clock, battery — deep lavender-slate

  # ── Gradient depth anchors ────────────────────────────────────
  # ~+14 / −8 steps around each WB tier, matching the Dawn approach.
  GRAD_SURFACE_HI = "#d2cee2";   # just above WB_SURFACE
  GRAD_SURFACE_LO = "#bcb8cc";   # just below WB_SURFACE
  GRAD_OVERLAY_HI = "#c8c4da";   # just above WB_OVERLAY
  GRAD_OVERLAY_LO = "#b2aec4";   # just below WB_OVERLAY
  GRAD_BASE_HI    = "#dad6ea";   # just above WB_BASE
  GRAD_BASE_LO    = "#c4c0d4";   # just below WB_BASE (≈ WB_SURFACE)

  # ── Accent border tints ───────────────────────────────────────
  # Midpoint of LOVE (#b06080) and ROSE (#c87880), darkened ~70% for border use.
  BORDER_ACCENT     = "#a86070";
  BORDER_ACCENT_RGB = "168,96,112";
  BORDER_IRIS_RGB   = "122,96,168";   # muted IRIS (#9070c0) for rgba()
  OVERLAY_RGB       = "226,218,240";  # RGB of OVERLAY (#e2daf0) for rgba()

  # ── Structural ────────────────────────────────────────────────
  INACTIVE_BORDER = "#c0bcd8";   # cool lavender-grey, subtle on the light desktop
  SHADOW          = "#5a5870";   # cool dark purple-grey — visible on light backgrounds

  # ── Derived tinted backgrounds ────────────────────────────────
  # PINE is periwinkle (#507aaa) so tints are pale blue-lavender washes.
  TINT_PINE_DARK   = "#d4daf0";   # progress bar / vol-30 periwinkle bg
  TINT_PINE_MID    = "#d8dcf4";   # sqlch notif / vol-20 / battery-full bg
  TINT_CRITICAL_BG = "#f0d8e4";   # critical notification — pale LOVE wash

  # ── State-tinted hover backgrounds ───────────────────────────
  # Pale washes — same semantic buckets as other palettes.
  HOVER_MUTED_BG  = "#e4e0f0";   # muted / vol-0 — pale lavender wash
  HOVER_TEAL_BG   = "#ccd4f0";   # cool / vol-5–15 — pale periwinkle wash (PINE)
  HOVER_GREEN_BG  = "#d0ecd8";   # warm-green / vol-35–55 — pale sage wash (FOAM)
  HOVER_GOLD_BG   = "#f0e4c0";   # gold / vol-60–65 — pale amber wash
  HOVER_ORANGE_BG = "#f2e0bc";   # amber / vol-70–75 — warm peach wash

  # ── Bar typography ───────────────────────────────────────────
  FONT_SIZE_BAR = "13px";
  ICON_SHADOW   = "0 1px 2px rgba(0,0,0,0.35)";

  # ── Box-shadow composition ────────────────────────────────────
  SHADOW_RGB     = "90,88,112";   # RGB of #5a5870 (cool purple-grey)
  SHADOW_A_OUTER = "0.10";
  SHADOW_A_DROP  = "0.07";
  SHADOW_A_HOVER = "0.10";
  INSET_TOP_A    = "0.50";        # visible glassy depth on light bg
  INSET_BOT_A    = "0.08";
  BORDER_TOP_A   = "0.65";        # visible shimmer on lavender-white bg
}
