#!/usr/bin/env bash
# ============================================================
# MPRIS Status — sqlch edition
# Bar:     icon  track title — artist
# Tooltip: album · year · genre(s) · time remaining
# Click:   notify-send with cover art
# ============================================================
set -euo pipefail
export LC_ALL=C

# ------------------------------------------------------------
# Config
# ------------------------------------------------------------
PREFERRED_PLAYERS=(sqlch mpv)
SNARK_FILE="$HOME/.config/waybar/snark.json"
# shellcheck source=/dev/null
source "$HOME/.config/waybar/palette.sh"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sqlch"
ENRICH_CACHE="$CACHE_DIR/enriched.json"
COVER_CACHE="$CACHE_DIR/covers"
mkdir -p "$COVER_CACHE"

# ------------------------------------------------------------
# Utilities
# ------------------------------------------------------------
pango_escape() {
  # Escape bare & < > in user-provided text so Pango markup doesn't choke
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' <<<"$1"
}

json_out() {
  local text="$1" tooltip="$2" class="$3"
  jq -nc \
    --arg text "$text" \
    --arg tooltip "$tooltip" \
    --arg class "$class" \
    '{text:$text, tooltip:$tooltip, class:$class}'
}

# ------------------------------------------------------------
# Player selection — prefer sqlch/mpv/ncspot/spotify, then anything Playing
# ------------------------------------------------------------

# ncspot and spotify register with instance-suffixed bus names
# (e.g. ncspot.instance99728), so we can't hard-code them in PREFERRED_PLAYERS.
# This resolves the first active player whose bus name starts with a given prefix.
find_player_by_prefix() {
  local prefix="$1"
  playerctl -l 2>/dev/null | grep "^${prefix}" | while read -r p; do
    if playerctl -p "$p" status 2>/dev/null | grep -q "Playing\|Paused"; then
      echo "$p"; return
    fi
  done
}

pick_player() {
  # ncspot/spotify are intentional foreground listens — check before always-on players
  for prefix in ncspot spotify; do
    p="$(find_player_by_prefix "$prefix")"
    [[ -n "$p" ]] && echo "$p" && return
  done
  for p in "${PREFERRED_PLAYERS[@]}"; do
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

if [[ -z "$PLAYER" ]]; then
  json_out "" "" "mpris stopped"
  exit 0
fi

STATUS="$(playerctl -p "$PLAYER" status 2>/dev/null || echo "Stopped")"

if [[ "$STATUS" == "Stopped" ]]; then
  json_out "" "" "mpris stopped"
  exit 0
fi

# ------------------------------------------------------------
# Core metadata from playerctl
# ------------------------------------------------------------
# sqlch exposes enriched metadata (album/year cache) on its MPRIS service but
# does NOT update title/artist when the ICY stream changes.  mpv always carries
# the live ICY title.  So: use sqlch for status/control, mpv for track info.
META_PLAYER="$PLAYER"
if [[ "$PLAYER" == "sqlch" ]] && playerctl -p mpv status 2>/dev/null | grep -q "Playing\|Paused"; then
  META_PLAYER="mpv"
fi

ARTIST="$(playerctl -p "$META_PLAYER" metadata artist 2>/dev/null || true)"
TITLE="$(playerctl -p "$META_PLAYER" metadata title 2>/dev/null || true)"
[[ -z "$TITLE" ]] && TITLE="Unknown Title"

# ncspot/spotify expose clean Spotify metadata — album and artUrl are available
# directly from MPRIS; collect them now so we can fall back to them below.
MPRIS_ALBUM="" MPRIS_ART_URL=""
if [[ "$PLAYER" == ncspot* || "$PLAYER" == spotify* ]]; then
  MPRIS_ALBUM="$(playerctl -p "$META_PLAYER" metadata album 2>/dev/null || true)"
  MPRIS_ART_URL="$(playerctl -p "$META_PLAYER" metadata mpris:artUrl 2>/dev/null || true)"
fi

# iHeart/terrestrial ICY streams embed metadata blobs directly in the title field.
# ncspot/spotify have clean metadata — skip this entire block for them.
# Two formats seen in the wild:
#
# Format 1 (music): title="Song",artist="Artist",url="song_spot=F" MediaBaseId=...
# Format 2 (ads/IDs): Ad Text - text="Station" song_spot="T" MediaBaseId=...
#
if [[ "$PLAYER" != ncspot* && "$PLAYER" != spotify* ]]; then
  _icy_f1='^title="([^"]*)".*,artist="([^"]*)"'
  _icy_spot=' song_spot="([^"]*)"'
  _icy_text=' text="([^"]*)"'
  if [[ "$TITLE" =~ $_icy_f1 ]]; then
    # Format 1: title="Song",artist="Artist",url="song_spot=F" MediaBaseId=...
    TITLE="${BASH_REMATCH[1]}"
    [[ -z "$ARTIST" ]] && ARTIST="${BASH_REMATCH[2]}"
  elif [[ "$TITLE" =~ song_spot= || "$TITLE" =~ MediaBaseId= ]]; then
    # Format 2: Content - text="value" song_spot="X" MediaBaseId=...
    # song_spot="M" → music: text= is song title, pre-dash content is artist
    # song_spot="T"/"C"/other → ad/station ID: pre-dash is the content, text= is station name
    icy_spot=""
    [[ "$TITLE" =~ $_icy_spot ]] && icy_spot="${BASH_REMATCH[1]}"
    icy_text=""
    [[ "$TITLE" =~ $_icy_text ]] && icy_text="${BASH_REMATCH[1]}"
    # Strip blob to get the raw text before the key=value section
    icy_pre="$(echo "$TITLE" | sed 's/ [A-Za-z_][A-Za-z0-9_]*=.*//')"
    icy_pre="${icy_pre% -}"
    icy_pre="${icy_pre% }"
    if [[ "$icy_spot" == "M" ]]; then
      TITLE="${icy_text:-$icy_pre}"
      [[ -z "$ARTIST" && -n "$icy_pre" ]] && ARTIST="$icy_pre"
    else
      TITLE="$icy_pre"
      [[ -z "$ARTIST" && -n "$icy_text" ]] && ARTIST="$icy_text"
    fi
  fi

  # Radio streams often pack "Artist - Track" into the title field with no separate artist.
  # Split on " - " when artist is still missing after ICY cleanup above.
  if [[ -z "$ARTIST" && "$TITLE" == *" - "* ]]; then
    ARTIST="${TITLE%% - *}"
    TITLE="${TITLE#* - }"
  fi
fi
[[ -z "$ARTIST" ]] && ARTIST="Unknown Artist"

# Time remaining
POSITION="$(playerctl -p "$PLAYER" position 2>/dev/null || echo 0)"
LENGTH_US="$(playerctl -p "$PLAYER" metadata mpris:length 2>/dev/null || echo 0)"
TIME_REMAINING=""
if [[ "$LENGTH_US" =~ ^[0-9]+$ ]] && (( LENGTH_US > 0 )); then
  LENGTH_S=$(( LENGTH_US / 1000000 ))
  POS_S=$(printf "%.0f" "$POSITION")
  REMAIN=$(( LENGTH_S - POS_S ))
  if (( REMAIN >= 0 )); then
    REMAIN_MIN=$(( REMAIN / 60 ))
    REMAIN_SEC=$(( REMAIN % 60 ))
    TIME_REMAINING="$(printf -- '-%d:%02d remaining' $REMAIN_MIN $REMAIN_SEC)"
  fi
fi

# ------------------------------------------------------------
# Enriched metadata from sqlch cache
# ------------------------------------------------------------
ALBUM="" YEAR="" GENRES="" COVER_URL=""

if [[ -f "$ENRICH_CACHE" ]]; then
  # Normalize key the same way enrich.py does: lowercase, collapse spaces, join with ::
  norm_artist="$(echo "$ARTIST" | tr '[:upper:]' '[:lower:]' | tr -s ' '  | sed 's/^ //;s/ $//')"
  norm_title="$(echo "$TITLE"  | tr '[:upper:]' '[:lower:]' | tr -s ' '  | sed 's/^ //;s/ $//')"
  CACHE_KEY="${norm_artist}::${norm_title}"

  ALBUM="$(jq -r --arg k "$CACHE_KEY" '.[$k].album // ""' "$ENRICH_CACHE" 2>/dev/null || true)"
  YEAR="$(jq -r  --arg k "$CACHE_KEY" '.[$k].year  // ""' "$ENRICH_CACHE" 2>/dev/null || true)"
  COVER_URL="$(jq -r --arg k "$CACHE_KEY" '.[$k].cover // ""' "$ENRICH_CACHE" 2>/dev/null || true)"
  GENRES="$(jq -r  --arg k "$CACHE_KEY" \
    'if (.[$k].genres | length) > 0 then .[$k].genres | join(", ") else "" end' \
    "$ENRICH_CACHE" 2>/dev/null || true)"
fi

# ------------------------------------------------------------
# Bar text
# ------------------------------------------------------------
case "$STATUS" in
  Playing) ICON="󰎆" ; CLASS="playing"  ;;
  Paused)  ICON="󰏤" ; CLASS="paused"   ;;
  *)       ICON="󰎈" ; CLASS="stopped"  ;;
esac

BAR_TEXT="$ICON $TITLE — $ARTIST"

# ------------------------------------------------------------
# Tooltip — use $'\n' for real newlines, waybar renders them
# ------------------------------------------------------------
TOOLTIP=""
if [[ -n "$ALBUM" || -n "$YEAR" ]]; then
  TOOLTIP+="<span foreground='${FOAM}'>$(pango_escape "$ALBUM")</span>"
  [[ -n "$YEAR" ]] && TOOLTIP+=" <span foreground='${SUBTLE}'>($(pango_escape "$YEAR"))</span>"
  TOOLTIP+=$'\n'
fi
[[ -n "$GENRES" ]] && TOOLTIP+="<span foreground='${IRIS}'>$(pango_escape "$GENRES")</span>"$'\n'
[[ -n "$TIME_REMAINING" ]] && TOOLTIP+="<span foreground='${GOLD}'>$TIME_REMAINING</span>"$'\n'
TOOLTIP+="<span foreground='${SUBTLE}'>$PLAYER</span>"
if [[ -f "$SNARK_FILE" ]] && command -v jq >/dev/null; then
  _snark=$(jq -r ".mpris.$(echo "$STATUS" | tr '[:upper:]' '[:lower:]')[]?" "$SNARK_FILE" 2>/dev/null | shuf -n1 || true)
  [[ -n "$_snark" && "$_snark" != "null" ]] && TOOLTIP+=$'\n'"<span foreground='${SUBTLE}'>────────────────────</span>"$'\n'"<span foreground='${IRIS}'>$_snark</span>"
fi

json_out "$BAR_TEXT" "$TOOLTIP" "$CLASS"
