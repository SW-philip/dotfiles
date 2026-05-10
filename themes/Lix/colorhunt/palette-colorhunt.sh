#!/usr/bin/env bash
# colorhunt — generated palette for waybar scripts

# ── Base colors ───────────────────────────────────────────────
BASE="#222831"
SURFACE="#37414f"
OVERLAY="#4c596d"
MUTED="#697583"
SUBTLE="#868e99"
TEXT="#ffffff"

# ── Accent spectrum (from secondary) ──────────────────────────
LOVE="#898e9c"
ROSE="#ffc9c9"
GOLD="#f4ff7c"
PINE="#00adb5"
FOAM="#96fff6"
IRIS="#eeeeee"

# ── Highlight tiers ───────────────────────────────────────────
HIGHLIGHT_LOW="#2c3440"
HIGHLIGHT_MED="#3b4555"
HIGHLIGHT_HIGH="#56657c"

# ── Structural ───────────────────────────────────────────────
SHADOW="#121418"
INACTIVE_BORDER="#3e4553"

# ── Waybar bar tiers ──────────────────────────────────────────
WB_BASE="#313946"
WB_SURFACE="#394352"
WB_OVERLAY="#434f61"

# ── Text roles ────────────────────────────────────────────────
TEXT_PRIMARY="$TEXT"
TEXT_SECONDARY="$SUBTLE"
INK="$TEXT_PRIMARY"

# ── Accent roles ──────────────────────────────────────────────
ACCENT_PRIMARY="#eeeeee"
ACCENT_SECONDARY="#eeeeee"
BORDER_ACCENT="#6e7484"

# ── Battery semantic colors ───────────────────────────────────
BATTERY_CRIT="#898e9c"
BATTERY_LOW="#f4ff7c"
BATTERY_MED="#ffc9c9"
BATTERY_HIGH="#96fff6"
BATTERY_FULL="#00adb5"

# ── Status roles ──────────────────────────────────────────────
WARN="$GOLD"
ERROR="$LOVE"
SUCCESS="$FOAM"
INFO="$IRIS"

# ── Weather semantic colors (glyph-only usage) ────────────────
WX_SUN_LIGHT="$GOLD"
WX_SUN_MEDIUM="$ROSE"
WX_SUN_HEAVY="$LOVE"

WX_RAIN_LIGHT="$FOAM"
WX_RAIN_MEDIUM="$ACCENT_SECONDARY"
WX_RAIN_HEAVY="$PINE"

WX_CLOUD_LIGHT="$TEXT_SECONDARY"
WX_CLOUD_MEDIUM="$SUBTLE"
WX_CLOUD_HEAVY="$MUTED"

WX_SNOW_LIGHT="$TEXT_PRIMARY"
WX_SNOW_HEAVY="$FOAM"

WX_FOG_LIGHT="$SUBTLE"
WX_FOG_HEAVY="$MUTED"

WX_STORM_HEAVY="$LOVE"
