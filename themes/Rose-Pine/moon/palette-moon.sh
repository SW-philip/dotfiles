#!/usr/bin/env bash
# Rosé Pine Moon — dark mode palette for waybar scripts
# Softer/cooler dark variant. Mirrors palette-moon.nix.

# Base colors
BASE="#232136"
SURFACE="#2a273f"
OVERLAY="#393552"
MUTED="#6e6a86"
SUBTLE="#908caa"
TEXT="#e0def4"
LOVE="#eb6f92"
GOLD="#f6c177"
ROSE="#ea9a97"
PINE="#3e8fb0"
FOAM="#9ccfd8"
IRIS="#c4a7e7"
HIGHLIGHT_LOW="#2a283e"
HIGHLIGHT_MED="#44415a"
HIGHLIGHT_HIGH="#56526e"

# Text roles
TEXT_PRIMARY="#e0def4"
TEXT_SECONDARY="#908caa"
INK="$TEXT_PRIMARY"

# Accent colors
ACCENT_PRIMARY="#c4a7e7"
ACCENT_SECONDARY="#9ccfd8"

# Battery semantic colors
BATTERY_CRIT="#eb6f92"
BATTERY_LOW="#f6c177"
BATTERY_MED="#ea9a97"
BATTERY_HIGH="#9ccfd8"
BATTERY_FULL="#3e8fb0"

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
