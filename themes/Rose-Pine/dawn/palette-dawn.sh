#!/usr/bin/env bash
# Rosé Pine Dawn — light mode palette for waybar scripts
# Mirrors palette-light.nix; swapped by toggle-theme alongside style.css.

# Base
BASE="#faf4ed"
SURFACE="#fffaf3"
OVERLAY="#f2e9e1"
MUTED="#8c8898"
SUBTLE="#797593"
TEXT="#575279"
LOVE="#b4637a"
GOLD="#ea9d34"
ROSE="#d7827e"
PINE="#286983"
FOAM="#56949f"
IRIS="#907aa9"
HIGHLIGHT_LOW="#f4ede8"
HIGHLIGHT_MED="#dfdad9"
HIGHLIGHT_HIGH="#cecacd"

# Text roles
TEXT_PRIMARY="#575279"
TEXT_SECONDARY="#797593"
INK="$TEXT_PRIMARY"

# Accent colors
ACCENT_PRIMARY="#907aa9"
ACCENT_SECONDARY="#56949f"

# Battery semantic colors
BATTERY_CRIT="#b4637a"
BATTERY_LOW="#ea9d34"
BATTERY_MED="#d7827e"
BATTERY_HIGH="#56949f"
BATTERY_FULL="#286983"

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
