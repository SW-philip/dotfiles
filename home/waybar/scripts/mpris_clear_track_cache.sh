#!/usr/bin/env bash
# ============================================================
# mpris_clear_track_cache.sh
# Right-click handler for the waybar mpris module.
# Removes the currently-playing track's entry from
# enriched.json so it gets re-fetched on the next poll.
# Does NOT touch the full metadata file — just the one key.
# ============================================================
set -euo pipefail
export LC_ALL=C

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sqlch"
ENRICH_CACHE="$CACHE_DIR/enriched.json"

# ------------------------------------------------------------
# Player selection — same logic as mpris_status.sh
# ------------------------------------------------------------
pick_player() {
  for p in sqlch mpv; do
    if playerctl -p "$p" status 2>/dev/null | grep -q "Playing\|Paused"; then
      echo "$p"; return
    fi
  done
  playerctl -l 2>/dev/null | while read -r p; do
    if playerctl -p "$p" status 2>/dev/null | grep -q "Playing"; then
      echo "$p"; return
    fi
  done
}

PLAYER="$(pick_player || true)"
[[ -z "$PLAYER" ]] && exit 0

# sqlch controls but mpv carries the live ICY title
META_PLAYER="$PLAYER"
if [[ "$PLAYER" == "sqlch" ]] && playerctl -p mpv status 2>/dev/null | grep -q "Playing\|Paused"; then
  META_PLAYER="mpv"
fi

ARTIST="$(playerctl -p "$META_PLAYER" metadata artist 2>/dev/null || true)"
TITLE="$(playerctl -p "$META_PLAYER"  metadata title  2>/dev/null || true)"
[[ -z "$TITLE" ]] && exit 0

# Unpack "Artist - Track" from title when artist field is empty
if [[ -z "$ARTIST" && "$TITLE" == *" - "* ]]; then
  ARTIST="${TITLE%% - *}"
  TITLE="${TITLE#* - }"
fi
[[ -z "$ARTIST" ]] && exit 0

# ------------------------------------------------------------
# Build the same cache key as mpris_status.sh / enrich.py
# ------------------------------------------------------------
norm_artist="$(echo "$ARTIST" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/^ //;s/ $//')"
norm_title="$(echo  "$TITLE"  | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/^ //;s/ $//')"
CACHE_KEY="${norm_artist}::${norm_title}"

# ------------------------------------------------------------
# Remove only the current track's entry from enriched.json
# ------------------------------------------------------------
if [[ ! -f "$ENRICH_CACHE" ]]; then
  notify-send --app-name="mpris" --urgency=low "Cache miss" "No enriched.json found"
  exit 0
fi

EXISTED="$(jq -r --arg k "$CACHE_KEY" 'has($k) | tostring' "$ENRICH_CACHE" 2>/dev/null || echo "false")"

if [[ "$EXISTED" == "true" ]]; then
  tmp="$(mktemp)"
  jq --arg k "$CACHE_KEY" 'del(.[$k])' "$ENRICH_CACHE" > "$tmp" && mv "$tmp" "$ENRICH_CACHE"
  notify-send --app-name="mpris" --urgency=low \
    "Cache cleared" "${ARTIST} — ${TITLE}"
else
  notify-send --app-name="mpris" --urgency=low \
    "Not cached" "${ARTIST} — ${TITLE}"
fi
