#!/usr/bin/env bash
# Rosé Pine Main — dark mode palette for waybar scripts

# Base colors
BASE="#191724"
SURFACE="#1f1d2e"
OVERLAY="#26233a"
MUTED="#6e6a86"
SUBTLE="#908caa"
TEXT="#e0def4"
LOVE="#eb6f92"
GOLD="#f6c177"
ROSE="#ebbcba"
PINE="#31748f"
FOAM="#9ccfd8"
IRIS="#c4a7e7"
HIGHLIGHT_LOW="#21202e"
HIGHLIGHT_MED="#403d52"
HIGHLIGHT_HIGH="#524f67"

# Text roles
TEXT_PRIMARY="#e0def4"
TEXT_SECONDARY="#908caa"
INK="$TEXT_PRIMARY"

# Accent colors
ACCENT_PRIMARY="#c4a7e7"
ACCENT_SECONDARY="#9ccfd8"
BLUE_1965_LIGHT="#9ccfd8"

# Battery semantic colors
BATTERY_CRIT="#eb6f92"
BATTERY_LOW="#f6c177"
BATTERY_MED="#ebbcba"
BATTERY_HIGH="#9ccfd8"
BATTERY_FULL="#31748f"

# Status colors
WARN="$GOLD"
ERROR="$LOVE"
SUCCESS="$FOAM"
INFO="$IRIS"

# ======================================================
# Weather semantic colors (glyph-only usage)
# ======================================================

# Sun / clear
WX_SUN_LIGHT="$GOLD"
WX_SUN_MEDIUM="$ROSE"
WX_SUN_HEAVY="$LOVE"

# Rain
WX_RAIN_LIGHT="$FOAM"
WX_RAIN_MEDIUM="$ACCENT_SECONDARY"
WX_RAIN_HEAVY="$PINE"

# Clouds / overcast / wind
WX_CLOUD_LIGHT="$TEXT_SECONDARY"
WX_CLOUD_MEDIUM="$SUBTLE"
WX_CLOUD_HEAVY="$MUTED"

# Snow
WX_SNOW_LIGHT="$TEXT_PRIMARY"
WX_SNOW_HEAVY="$FOAM"

# Fog / haze
WX_FOG_LIGHT="$SUBTLE"
WX_FOG_HEAVY="$MUTED"

# Storms
WX_STORM_HEAVY="$LOVE"
