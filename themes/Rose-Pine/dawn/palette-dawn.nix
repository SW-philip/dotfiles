# Rosé Pine Dawn — light mode companion to palette.nix
# All keys are identical to palette.nix so swapping the import is the only
# change needed to flip the entire theme.
{
  # ── Base ──────────────────────────────────────────────────────
  BASE           = "#faf4ed";
  SURFACE        = "#fffaf3";
  OVERLAY        = "#f2e9e1";
  HIGHLIGHT_LOW  = "#f4ede8";
  HIGHLIGHT_MED  = "#dfdad9";
  HIGHLIGHT_HIGH = "#cecacd";

  # ── Text & accents ────────────────────────────────────────────
  MUTED  = "#8c8898";
  SUBTLE = "#797593";
  TEXT   = "#575279";
  LOVE   = "#b4637a";
  ROSE   = "#d7827e";
  GOLD   = "#ea9d34";
  PINE   = "#286983";
  FOAM   = "#56949f";
  IRIS   = "#907aa9";

  # ── Extended — named system-state colors ──────────────────────
  CRITICAL   = "#b4637a";   # LOVE (Dawn)
  WARNING    = "#ea9d34";   # GOLD (Dawn)
  CAUTION    = "#7a9420";   # muted yellow-green readable on light bg
  MUTED_ICON = "#6b6680";   # darkened for contrast on slate grey backgrounds

  # ── Semantic aliases ──────────────────────────────────────────
  TEXT_PRIMARY   = "#575279";
  TEXT_SECONDARY = "#797593";
  ACCENT_PRIMARY   = "#907aa9";
  ACCENT_SECONDARY = "#56949f";

  # ── Battery ───────────────────────────────────────────────────
  BATTERY_FULL = "#286983";
  BATTERY_HIGH = "#56949f";
  BATTERY_MED  = "#d7827e";
  BATTERY_LOW  = "#ea9d34";
  BATTERY_CRIT = "#b4637a";

  # ── Waybar module background tiers ───────────────────────────
  # Slate grey — clearly grey (not cream/white) on a light desktop.
  # Maintains the same depth order as dark mode (OVERLAY = darkest/most elevated).
  WB_BASE    = "#d0d4da";   # tray, pill groups — light slate
  WB_SURFACE = "#c8cdd4";   # weather, volume, mpris, cpu_temp — mid slate
  WB_OVERLAY = "#bfc4cb";   # clock, battery — deep slate

  # ── Gradient depth anchors ────────────────────────────────────
  # Anchored around the new slate WB tiers.
  GRAD_SURFACE_HI = "#d4d9e0";   # just above WB_SURFACE
  GRAD_SURFACE_LO = "#c0c5cc";   # just below WB_SURFACE
  GRAD_OVERLAY_HI = "#ccd1d8";   # just above WB_OVERLAY
  GRAD_OVERLAY_LO = "#b8bdc4";   # just below WB_OVERLAY
  GRAD_BASE_HI    = "#dce0e6";   # just above WB_BASE
  GRAD_BASE_LO    = "#c8cdd4";   # just below WB_BASE (≈ WB_SURFACE)

  # ── Accent border tints ───────────────────────────────────────
  # Midpoint of Dawn LOVE (#b4637a) and Dawn ROSE (#d7827e) = #c57078.
  # Kept slightly muted so borders stay subtle on the light surface.
  BORDER_ACCENT     = "#c07080";
  BORDER_ACCENT_RGB = "192,112,128";
  BORDER_IRIS_RGB   = "125,104,150";   # muted Dawn IRIS (#907aa9) for rgba()
  OVERLAY_RGB       = "242,233,225";   # RGB of OVERLAY (#f2e9e1) for rgba()

  # ── Structural ────────────────────────────────────────────────
  INACTIVE_BORDER = "#d0c8cc";   # warm gray-purple between HIGHLIGHT_MED/HIGH
  SHADOW          = "#706868";   # warm dark gray — visible on light backgrounds

  # ── Derived tinted backgrounds ────────────────────────────────
  # Light equivalents of the dark PINE/LOVE tints; these are pale washes.
  TINT_PINE_DARK   = "#d4e8ec";   # light teal wash (vol-30 / progress bg)
  TINT_PINE_MID    = "#d8eaee";   # lighter teal wash (vol-20 / battery-full bg)
  TINT_CRITICAL_BG = "#f5dce2";   # pale rose wash (critical notification bg)

  # ── State-tinted hover backgrounds ───────────────────────────
  # Pale washes — same semantic buckets as dark palette.
  HOVER_MUTED_BG  = "#e6e2ea";   # muted / vol-0 — pale lavender wash
  HOVER_TEAL_BG   = "#cce6ec";   # cool / vol-5–15 — pale teal wash
  HOVER_GREEN_BG  = "#d4ecda";   # warm-green / vol-35–55 — pale sage wash
  HOVER_GOLD_BG   = "#f0eacc";   # gold / vol-60–65 — pale gold wash
  HOVER_ORANGE_BG = "#f5e4cc";   # amber / vol-70–75 — pale peach wash

  # ── Bar typography ───────────────────────────────────────────
  FONT_SIZE_BAR = "13px";
  ICON_SHADOW   = "0 1px 2px rgba(0,0,0,0.35)";

  # ── Box-shadow composition ────────────────────────────────────
  # Lighter values so shadows don't look like black rings on a cream background.
  SHADOW_RGB     = "112,104,104";  # RGB of #706868 (warm gray — Dawn SHADOW)
  SHADOW_A_OUTER = "0.10";
  SHADOW_A_DROP  = "0.07";
  SHADOW_A_HOVER = "0.10";
  INSET_TOP_A    = "0.50";         # more visible on light for glassy depth
  INSET_BOT_A    = "0.08";
  BORDER_TOP_A   = "0.65";         # visible white shimmer on cream bg
}
