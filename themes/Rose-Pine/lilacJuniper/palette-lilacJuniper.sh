#!/usr/bin/env bash
# Lilac-Juniper — custom light variant for waybar scripts
# Cool lavender-white base; juniper-patina blue + forest sage + lilac + amber accents.
# Mirrors palette-lilac-juniper.nix.

# Base colors
BASE="#f4f0fc"
SURFACE="#ede8f8"
OVERLAY="#e2daf0"
MUTED="#9088b8"
SUBTLE="#7a72a0"
TEXT="#3e3868"
LOVE="#b06080"
GOLD="#c87820"
ROSE="#c87880"
PINE="#507aaa"
FOAM="#5a8a6a"
IRIS="#9070c0"
HIGHLIGHT_LOW="#eee8f8"
HIGHLIGHT_MED="#dbd4ec"
HIGHLIGHT_HIGH="#c8c0e0"

# Text roles
TEXT_PRIMARY="#3e3868"
TEXT_SECONDARY="#7a72a0"
INK="$TEXT_PRIMARY"

# Accent colors
ACCENT_PRIMARY="#9070c0"
ACCENT_SECONDARY="#507aaa"

# Battery semantic colors
BATTERY_CRIT="#b06080"
BATTERY_LOW="#c87820"
BATTERY_MED="#c87880"
BATTERY_HIGH="#5a8a6a"
BATTERY_FULL="#507aaa"

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
