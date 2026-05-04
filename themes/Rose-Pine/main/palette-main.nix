# Rosé Pine Main — nix mirror of home/waybar/palette.sh
# Keep in sync with palette.sh when updating colors.
{
  # ── Base ──────────────────────────────────────────────────────
  BASE           = "#191724";
  SURFACE        = "#1f1d2e";
  OVERLAY        = "#26233a";
  HIGHLIGHT_LOW  = "#21202e";
  HIGHLIGHT_MED  = "#403d52";
  HIGHLIGHT_HIGH = "#524f67";

  # ── Text & accents ────────────────────────────────────────────
  MUTED  = "#6e6a86";
  SUBTLE = "#908caa";
  TEXT   = "#e0def4";
  LOVE   = "#eb6f92";
  ROSE   = "#ebbcba";
  GOLD   = "#f6c177";
  PINE   = "#31748f";
  FOAM   = "#9ccfd8";
  IRIS   = "#c4a7e7";

  # ── Extended — named system-state colors ──────────────────────
  CRITICAL   = "#f040a0";
  WARNING    = "#f0a020";
  CAUTION    = "#c8db38";
  MUTED_ICON = "#c4c0d8";

  # ── Semantic aliases ──────────────────────────────────────────
  TEXT_PRIMARY   = "#e0def4";
  TEXT_SECONDARY = "#908caa";
  ACCENT_PRIMARY   = "#c4a7e7";
  ACCENT_SECONDARY = "#9ccfd8";

  # ── Battery ───────────────────────────────────────────────────
  BATTERY_FULL = "#31748f";
  BATTERY_HIGH = "#9ccfd8";
  BATTERY_MED  = "#ebbcba";
  BATTERY_LOW  = "#f6c177";
  BATTERY_CRIT = "#eb6f92";

  # ── Waybar module background tiers ───────────────────────────
  # Mapped to BASE/SURFACE/OVERLAY in dark mode (no change).
  # Light mode uses different values to step them down from near-white.
  WB_BASE    = "#191724";   # tray, pill groups
  WB_SURFACE = "#1f1d2e";   # weather, volume, mpris, cpu_temp
  WB_OVERLAY = "#26233a";   # clock, battery

  # ── Gradient depth anchors ────────────────────────────────────
  # These are the dark-theme step values that give widgets layered depth.
  # All six change for a light theme — update them there too.
  GRAD_SURFACE_HI = "#252238";   # surface-tier widget gradient top
  GRAD_SURFACE_LO = "#1c1a2e";   # surface-tier widget gradient bottom
  GRAD_OVERLAY_HI = "#2e2a42";   # elevated/hover gradient top
  GRAD_OVERLAY_LO = "#231f38";   # elevated/hover gradient bottom
  GRAD_BASE_HI    = "#201e30";   # base-tier top & dim-hover bg
  GRAD_BASE_LO    = "#181624";   # base-tier widget gradient bottom

  # ── Accent border tints ───────────────────────────────────────
  # Used as rgba() in CSS; the _RGB variant lets you write
  # rgba(${p.BORDER_ACCENT_RGB},0.18) without re-deriving the components.
  BORDER_ACCENT     = "#a86077";    # LOVE/ROSE midpoint for module borders
  BORDER_ACCENT_RGB = "168,96,119"; # RGB components of BORDER_ACCENT
  BORDER_IRIS_RGB   = "136,114,170"; # RGB components of IRIS tint (#8872aa)
  OVERLAY_RGB       = "38,35,58";   # RGB of OVERLAY (#26233a) for rgba()

  # ── Structural ────────────────────────────────────────────────
  INACTIVE_BORDER = "#393552";   # niri inactive window border
  SHADOW          = "#0d0c0f";   # shadow base — append alpha hex as needed

  # ── Derived tinted backgrounds ────────────────────────────────
  # Darkened accent tints used for notification and thermal hover backgrounds.
  TINT_PINE_DARK   = "#153a36";  # progress bar / vol-30 teal bg
  TINT_PINE_MID    = "#163234";  # sqlch notif / vol-20 / battery-full bg
  TINT_CRITICAL_BG = "#38081a";  # critical notification background

  # ── State-tinted hover backgrounds ───────────────────────────
  # Semantic thermal/state buckets shared by volume, cpu, battery, network.
  # Dark values approximate the original per-step hand-tuned backgrounds.
  HOVER_MUTED_BG  = "#1e1e2a";  # muted / vol-0
  HOVER_TEAL_BG   = "#192630";  # cool / vol-5–15 / network-high / battery-high
  HOVER_GREEN_BG  = "#1c3e28";  # warm-green / vol-35–55 / battery-med / cpu-warm
  HOVER_GOLD_BG   = "#3e3808";  # gold / vol-60–65
  HOVER_ORANGE_BG = "#4a2808";  # amber / vol-70–75 / battery-low / cpu-hot

  # ── Bar typography ───────────────────────────────────────────
  FONT_SIZE_BAR = "12px";
  ICON_SHADOW   = "0 1px 2px rgba(0,0,0,0.80)";

  # ── Box-shadow composition ────────────────────────────────────
  # These vary between dark and light so the same CSS template works for both.
  SHADOW_RGB     = "0,0,0";    # RGB components of drop-shadow base
  SHADOW_A_OUTER = "0.50";     # outer definition ring (0 0 0 1px)
  SHADOW_A_DROP  = "0.55";     # ambient drop shadow
  SHADOW_A_HOVER = "0.65";     # drop shadow on hover
  INSET_TOP_A    = "0.08";     # top inset highlight (light source illusion)
  INSET_BOT_A    = "0.30";     # bottom inset shadow
  BORDER_TOP_A   = "0.07";     # border-top white shimmer
}
