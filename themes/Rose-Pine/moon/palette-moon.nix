# Rosé Pine Moon — nix mirror of home/waybar/palette-moon.sh
# Softer/cooler dark variant. Keep in sync with palette-moon.sh when updating colors.
{
  # ── Base ──────────────────────────────────────────────────────
  BASE           = "#232136";
  SURFACE        = "#2a273f";
  OVERLAY        = "#393552";
  HIGHLIGHT_LOW  = "#2a283e";
  HIGHLIGHT_MED  = "#44415a";
  HIGHLIGHT_HIGH = "#56526e";

  # ── Text & accents ────────────────────────────────────────────
  MUTED  = "#6e6a86";
  SUBTLE = "#908caa";
  TEXT   = "#e0def4";
  LOVE   = "#eb6f92";
  ROSE   = "#ea9a97";
  GOLD   = "#f6c177";
  PINE   = "#3e8fb0";
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
  BATTERY_FULL = "#3e8fb0";
  BATTERY_HIGH = "#9ccfd8";
  BATTERY_MED  = "#ea9a97";
  BATTERY_LOW  = "#f6c177";
  BATTERY_CRIT = "#eb6f92";

  # ── Waybar module background tiers ───────────────────────────
  WB_BASE    = "#232136";   # tray, pill groups
  WB_SURFACE = "#2a273f";   # weather, volume, mpris, cpu_temp
  WB_OVERLAY = "#393552";   # clock, battery

  # ── Gradient depth anchors ────────────────────────────────────
  # ~+6 / −3 steps around each tier, matching the Main approach.
  GRAD_SURFACE_HI = "#302c47";   # surface-tier widget gradient top
  GRAD_SURFACE_LO = "#27243f";   # surface-tier widget gradient bottom
  GRAD_OVERLAY_HI = "#413c5a";   # elevated/hover gradient top
  GRAD_OVERLAY_LO = "#363150";   # elevated/hover gradient bottom
  GRAD_BASE_HI    = "#2a2842";   # base-tier top & dim-hover bg
  GRAD_BASE_LO    = "#222036";   # base-tier widget gradient bottom

  # ── Accent border tints ───────────────────────────────────────
  # LOVE (#eb6f92) / Moon ROSE (#ea9a97) midpoint, darkened ~70%.
  BORDER_ACCENT     = "#a6556b";
  BORDER_ACCENT_RGB = "166,85,107";
  BORDER_IRIS_RGB   = "136,114,170";   # same as Main — IRIS is unchanged
  OVERLAY_RGB       = "57,53,82";      # RGB of OVERLAY (#393552) for rgba()

  # ── Structural ────────────────────────────────────────────────
  INACTIVE_BORDER = "#4a4565";   # between OVERLAY and HIGHLIGHT_HIGH
  SHADOW          = "#0d0c0f";

  # ── Derived tinted backgrounds ────────────────────────────────
  # Moon's PINE is bluer (#3e8fb0), so tints shift toward blue-teal.
  TINT_PINE_DARK   = "#14323e";
  TINT_PINE_MID    = "#122e3a";
  TINT_CRITICAL_BG = "#38081a";   # LOVE is unchanged — same as Main

  # ── State-tinted hover backgrounds ───────────────────────────
  HOVER_MUTED_BG  = "#1f1e2e";   # muted / vol-0
  HOVER_TEAL_BG   = "#172838";   # cool / vol-5–15 — slightly more blue than Main
  HOVER_GREEN_BG  = "#1c3e28";   # warm-green / vol-35–55
  HOVER_GOLD_BG   = "#3e3808";   # gold / vol-60–65
  HOVER_ORANGE_BG = "#4a2808";   # amber / vol-70–75

  # ── Bar typography ───────────────────────────────────────────
  FONT_SIZE_BAR = "12px";
  ICON_SHADOW   = "0 1px 2px rgba(0,0,0,0.80)";

  # ── Box-shadow composition ────────────────────────────────────
  SHADOW_RGB     = "0,0,0";
  SHADOW_A_OUTER = "0.50";
  SHADOW_A_DROP  = "0.55";
  SHADOW_A_HOVER = "0.65";
  INSET_TOP_A    = "0.40";
  INSET_BOT_A    = "0.20";
  BORDER_TOP_A   = "0.50";
}
