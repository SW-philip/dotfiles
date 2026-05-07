#!/usr/bin/env bash
# ============================================================
# sqlch cover art notification
# Called by waybar on-click for the mpris module.
# Downloads cover art from the enriched cache and fires
# a notify-send with the image.
# ============================================================
set -euo pipefail
export LC_ALL=C

# Spotify creds live in a secret file; waybar is a systemd service so .zshrc is
# never sourced — load them here so token refresh works.
[ -f /run/secrets/spotify_env ] && source /run/secrets/spotify_env

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sqlch"
ENRICH_CACHE="$CACHE_DIR/enriched.json"
COVER_CACHE="$CACHE_DIR/covers"
mkdir -p "$COVER_CACHE"

# ------------------------------------------------------------
# Player selection — mirrors mpris_status.sh priority order
# ------------------------------------------------------------
find_player_by_prefix() {
  local prefix="$1"
  playerctl -l 2>/dev/null | grep "^${prefix}" | while read -r p; do
    if playerctl -p "$p" status 2>/dev/null | grep -q "Playing\|Paused"; then
      echo "$p"; return
    fi
  done
}

pick_player() {
  for prefix in ncspot spotify; do
    p="$(find_player_by_prefix "$prefix")"
    [[ -n "$p" ]] && echo "$p" && return
  done
  for p in sqlch mpv; do
    if playerctl -p "$p" status 2>/dev/null | grep -q "Playing\|Paused"; then
      echo "$p"; return
    fi
  done
}

PLAYER="$(pick_player || true)"
[[ -z "$PLAYER" ]] && exit 0

# sqlch controls playback but mpv carries the live ICY title
META_PLAYER="$PLAYER"
if [[ "$PLAYER" == "sqlch" ]] && playerctl -p mpv status 2>/dev/null | grep -q "Playing\|Paused"; then
  META_PLAYER="mpv"
fi

ARTIST="$(playerctl -p "$META_PLAYER" metadata artist 2>/dev/null || true)"
TITLE="$(playerctl -p "$META_PLAYER"  metadata title  2>/dev/null || true)"
[[ -z "$TITLE" ]] && TITLE="Unknown Title"

ALBUM="" YEAR="" GENRES="" COVER_URL=""

# ncspot/spotify: metadata and cover art come directly from MPRIS
if [[ "$PLAYER" == ncspot* || "$PLAYER" == spotify* ]]; then
  ALBUM="$(playerctl -p "$META_PLAYER" metadata album       2>/dev/null || true)"
  COVER_URL="$(playerctl -p "$META_PLAYER" metadata mpris:artUrl 2>/dev/null || true)"
  [[ -z "$ARTIST" ]] && ARTIST="Unknown Artist"
else
  # iHeart/terrestrial ICY metadata blob parsing
  _icy_f1='^title="([^"]*)".*,artist="([^"]*)"'
  _icy_spot=' song_spot="([^"]*)"'
  _icy_text=' text="([^"]*)"'
  if [[ "$TITLE" =~ $_icy_f1 ]]; then
    TITLE="${BASH_REMATCH[1]}"
    [[ -z "$ARTIST" ]] && ARTIST="${BASH_REMATCH[2]}"
  elif [[ "$TITLE" =~ song_spot= || "$TITLE" =~ MediaBaseId= ]]; then
    icy_spot=""; [[ "$TITLE" =~ $_icy_spot ]] && icy_spot="${BASH_REMATCH[1]}"
    icy_text=""; [[ "$TITLE" =~ $_icy_text ]] && icy_text="${BASH_REMATCH[1]}"
    icy_pre="$(echo "$TITLE" | sed 's/ [A-Za-z_][A-Za-z0-9_]*=.*//')"
    icy_pre="${icy_pre% -}"; icy_pre="${icy_pre% }"
    if [[ "$icy_spot" == "M" ]]; then
      TITLE="${icy_text:-$icy_pre}"
      [[ -z "$ARTIST" && -n "$icy_pre" ]] && ARTIST="$icy_pre"
    else
      TITLE="$icy_pre"
      [[ -z "$ARTIST" && -n "$icy_text" ]] && ARTIST="$icy_text"
    fi
  fi
  if [[ -z "$ARTIST" && "$TITLE" == *" - "* ]]; then
    ARTIST="${TITLE%% - *}"
    TITLE="${TITLE#* - }"
  fi
  [[ -z "$ARTIST" ]] && ARTIST="Unknown Artist"

  # sqlch enrichment cache for album/year/genres/cover
  norm_artist="$(echo "$ARTIST" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/^ //;s/ $//')"
  norm_title="$(echo  "$TITLE"  | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/^ //;s/ $//')"
  CACHE_KEY="${norm_artist}::${norm_title}"

  NEEDS_ENRICH=false
  if [[ ! -f "$ENRICH_CACHE" ]]; then
    NEEDS_ENRICH=true
  else
    CACHED_COVER="$(jq -r --arg k "$CACHE_KEY" '.[$k].cover // "MISSING"' "$ENRICH_CACHE" 2>/dev/null || echo "MISSING")"
    [[ "$CACHED_COVER" == "MISSING" || "$CACHED_COVER" == "null" || -z "$CACHED_COVER" ]] && NEEDS_ENRICH=true
  fi

  if [[ "$NEEDS_ENRICH" == true ]]; then
    ENRICH_ARTIST="$ARTIST" ENRICH_TITLE="$TITLE" python3 -c "
import sys, os
sys.path.insert(0, os.path.expanduser('~/sqlch'))
from sqlch.core import enrich
enrich.enrich_track(os.environ['ENRICH_ARTIST'], os.environ['ENRICH_TITLE'])
" 2>/dev/null || true
  fi

  if [[ -f "$ENRICH_CACHE" ]]; then
    ALBUM="$(    jq -r --arg k "$CACHE_KEY" '.[$k].album // ""' "$ENRICH_CACHE" 2>/dev/null || true)"
    YEAR="$(     jq -r --arg k "$CACHE_KEY" '.[$k].year  // ""' "$ENRICH_CACHE" 2>/dev/null || true)"
    COVER_URL="$(jq -r --arg k "$CACHE_KEY" '.[$k].cover // ""' "$ENRICH_CACHE" 2>/dev/null || true)"
    GENRES="$(   jq -r --arg k "$CACHE_KEY" \
      'if (.[$k].genres | length) > 0 then .[$k].genres | join(", ") else "" end' \
      "$ENRICH_CACHE" 2>/dev/null || true)"
  fi
fi

# ------------------------------------------------------------
# Download cover art if we have a URL
# ------------------------------------------------------------
COVER_PATH=""
if [[ -n "$COVER_URL" && "$COVER_URL" != "null" ]]; then
  # Use URL hash as filename to avoid re-downloading
  URL_HASH="$(echo "$COVER_URL" | md5sum | cut -d' ' -f1)"
  COVER_PATH="$COVER_CACHE/${URL_HASH}.jpg"
  if [[ ! -f "$COVER_PATH" ]]; then
    curl -fsSL "$COVER_URL" -o "$COVER_PATH" 2>/dev/null || COVER_PATH=""
  fi
fi

# ------------------------------------------------------------
# Build notification body
# ------------------------------------------------------------
BODY="$ARTIST"
[[ -n "$ALBUM" ]] && BODY+=$'\n'"$ALBUM"
[[ -n "$YEAR" ]]  && BODY+=" ($YEAR)"
[[ -n "$GENRES" ]] && BODY+=$'\n'"$GENRES"

# ------------------------------------------------------------
# Fire notification
# ------------------------------------------------------------
NOTIFY_ARGS=(
  --app-name="sqlch"
  --urgency=low
  --expire-time=8000
  "$TITLE"
  "$BODY"
)

if [[ -n "$COVER_PATH" && -f "$COVER_PATH" ]]; then
  notify-send --icon="$COVER_PATH" "${NOTIFY_ARGS[@]}"
else
  notify-send "${NOTIFY_ARGS[@]}"
fi
