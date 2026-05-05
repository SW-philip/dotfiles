#!/usr/bin/env bash
# Resolve album art for hyprlock from the sqlch enrichment cache.
# mpris:artUrl is not published by either sqlch or mpv, so we look up
# the current track in enriched.json (same cache the popup uses).
# Always writes to a fixed CURRENT symlink so hyprlock's path= stays stable.

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sqlch"
COVER_CACHE="$CACHE_DIR/covers"
ENRICH_CACHE="$CACHE_DIR/enriched.json"
CURRENT="$COVER_CACHE/current.jpg"
mkdir -p "$COVER_CACHE"

# hyprlock's reload_cmd may not inherit DBUS_SESSION_BUS_ADDRESS
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

# ------------------------------------------------------------
# Get current track from mpv (has live ICY title; sqlch cache is stale)
# ------------------------------------------------------------
ARTIST=""
TITLE=""

if playerctl -p mpv status 2>/dev/null | grep -q "Playing\|Paused"; then
  META_PLAYER="mpv"
elif playerctl -p sqlch status 2>/dev/null | grep -q "Playing\|Paused"; then
  META_PLAYER="sqlch"
else
  echo "$CURRENT"
  exit 0
fi

ARTIST="$(playerctl -p "$META_PLAYER" metadata artist 2>/dev/null || true)"
TITLE="$(playerctl -p "$META_PLAYER"  metadata title  2>/dev/null || true)"

# Radio ICY streams pack "Artist - Track" into title with no separate artist
if [[ -z "$ARTIST" && "$TITLE" == *" - "* ]]; then
  ARTIST="${TITLE%% - *}"
  TITLE="${TITLE#* - }"
fi

if [[ -z "$TITLE" ]]; then
  echo "$CURRENT"
  exit 0
fi

# ------------------------------------------------------------
# Look up cover URL in enrichment cache
# ------------------------------------------------------------
norm_artist="$(echo "$ARTIST" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/^ //;s/ $//')"
norm_title="$(echo  "$TITLE"  | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/^ //;s/ $//')"
CACHE_KEY="${norm_artist}::${norm_title}"

COVER_URL=""
if [[ -f "$ENRICH_CACHE" ]]; then
  COVER_URL="$(jq -r --arg k "$CACHE_KEY" '.[$k].cover // ""' "$ENRICH_CACHE" 2>/dev/null || true)"
fi

if [[ -z "$COVER_URL" || "$COVER_URL" == "null" ]]; then
  echo "$CURRENT"
  exit 0
fi

# ------------------------------------------------------------
# Download if not cached, then update the current symlink
# ------------------------------------------------------------
URL_HASH="$(echo -n "$COVER_URL" | md5sum | cut -d' ' -f1)"
CACHED="$COVER_CACHE/art_${URL_HASH}.jpg"

if [[ ! -f "$CACHED" ]]; then
  curl -fsSL --max-time 5 -o "$CACHED" "$COVER_URL" 2>/dev/null || rm -f "$CACHED"
fi

if [[ -f "$CACHED" ]]; then
  ln -sf "$CACHED" "$CURRENT"
fi

echo "$CURRENT"
