#!/usr/bin/env bash
# ==========================================================
# Quantum Clock — v3
# Modes: moon (default) · hex · progress · natural
# Modes latch until cycled back to moon.
# Hourly surprise fires from default mode only.
# Lunar phase: synodic reference-epoch method (accurate).
# ==========================================================
set -euo pipefail

# shellcheck source=/dev/null
source "$HOME/.config/waybar/palette.sh"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quantum_clock"
MODE_FILE="$CACHE_DIR/mode"
H24_FILE="$CACHE_DIR/24h"
HOURLY_FILE="$CACHE_DIR/hourly_show"

CLOCK_DEFAULT="moon"
CLOCK_MODES=(moon hex progress natural caliper)

: "${CLOCK_TZ:=}"
CLOCK_24H=$(cat "$H24_FILE" 2>/dev/null || echo "0")

mkdir -p "$CACHE_DIR"
[[ -f "$MODE_FILE" ]] || echo "$CLOCK_DEFAULT" > "$MODE_FILE"

# ── Time helpers ──────────────────────────────────────────

_now() {
  [[ -n "$CLOCK_TZ" ]] && TZ="$CLOCK_TZ" date +%s || date +%s
}

_date() {   # wrapper: runs date with optional TZ
  if [[ -n "$CLOCK_TZ" ]]; then
    TZ="$CLOCK_TZ" date "$@"
  else
    date "$@"
  fi
}

_fmt() {    # HH:MM (no seconds) for bar display
  local ep="$1"
  if [[ "$CLOCK_24H" == "1" ]]; then
    _date -d "@$ep" "+%H:%M"
  else
    _date -d "@$ep" "+%-I:%M %p"
  fi
}

_fmt_sec() {  # HH:MM:SS for tooltip
  local ep="$1"
  if [[ "$CLOCK_24H" == "1" ]]; then
    _date -d "@$ep" "+%H:%M:%S"
  else
    _date -d "@$ep" "+%-I:%M:%S %p"
  fi
}

_wrap_json() {
  # Only escape double-quotes; leave \n sequences intact (waybar renders them).
  printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
    "$(sed 's/"/\\"/g' <<<"$1")" \
    "$(sed 's/"/\\"/g' <<<"$2")" \
    "$(sed 's/"/\\"/g' <<<"$3")"
}

# ── Mode cycling ──────────────────────────────────────────

_current_mode() { cat "$MODE_FILE" 2>/dev/null || echo "$CLOCK_DEFAULT"; }

_next_mode() {
  local cur; cur=$(_current_mode)
  local n=${#CLOCK_MODES[@]}
  for i in "${!CLOCK_MODES[@]}"; do
    if [[ "${CLOCK_MODES[$i]}" == "$cur" ]]; then
      echo "${CLOCK_MODES[$(( (i+1) % n ))]}" > "$MODE_FILE"
      return
    fi
  done
  echo "${CLOCK_MODES[0]}" > "$MODE_FILE"
}

# ── Tooltip base (same regardless of mode) ────────────────

_tooltip_base() {
  local ep="$1"
  local weekday datestr weeknum dayofyear year dow total_days

  weekday=$( _date -d "@$ep" "+%A")
  datestr=$(  _date -d "@$ep" "+%-d %B %Y")
  weeknum=$(  _date -d "@$ep" "+%-V")
  dayofyear=$(date -d "@$ep" "+%-j")
  year=$(     date -d "@$ep" "+%Y")
  dow=$(      date -d "@$ep" "+%u")   # 1=Mon … 7=Sun

  if (( year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) )); then
    total_days=366
  else
    total_days=365
  fi

  local weekend_line=""
  case "$dow" in
    1) weekend_line="\n<span foreground='${GOLD}'>4 days until the weekend</span>" ;;
    2) weekend_line="\n<span foreground='${GOLD}'>3 days until the weekend</span>" ;;
    3) weekend_line="\n<span foreground='${GOLD}'>2 days until the weekend</span>" ;;
    4) weekend_line="\n<span foreground='${GOLD}'>1 day until the weekend</span>" ;;
    5) weekend_line="\n<span foreground='${IRIS}'>weekend starts tomorrow</span>" ;;
    6|7) weekend_line="" ;;
  esac

  echo "<span foreground='${SUBTLE}'>${weekday}</span>, <span foreground='${TEXT}'>${datestr}</span>\n<span foreground='${SUBTLE}'>Week ${weeknum} · Day ${dayofyear} of ${total_days}</span>${weekend_line}\n<span foreground='${FOAM}'>$(_fmt_sec "$ep")</span>"
}

# ── Lunar phase ───────────────────────────────────────────
# Reference new moon: 2000-01-06 18:14 UTC = JD 2451550.259
# Synodic period: 29.530588853 days
# Returns pipe-separated: glyph|name|illum%|days_to_full|days_to_new

_lunar() {
  local ep; ep="$(_now)"

  read -r phase_days illum phase_idx <<< "$(awk -v t="$ep" 'BEGIN {
    pi      = 3.141592653589793
    synodic = 29.530588853
    jd      = t / 86400.0 + 2440587.5
    ref_new = 2451550.259

    frac = (jd - ref_new) / synodic
    frac = frac - int(frac)
    if (frac < 0) frac += 1

    phase_days = frac * synodic
    illum      = int((1 - cos(frac * 2 * pi)) / 2 * 100 + 0.5)
    phase_idx  = int(frac * 8 + 0.5) % 8

    printf "%.2f %d %d\n", phase_days, illum, phase_idx
  }')"

  local -a names=(
    "New Moon"       "Waxing Crescent" "First Quarter"  "Waxing Gibbous"
    "Full Moon"      "Waning Gibbous"  "Last Quarter"   "Waning Crescent"
  )
  local -a glyphs=( "󰽤" "󰽧" "󰽡" "󰽨" "󰽢" "󰽦" "󰽣" "󰽥" )

  local days_to_full days_to_new
  days_to_full=$(awk -v pd="$phase_days" -v syn=29.530588853 'BEGIN {
    half = syn / 2
    d    = half - pd
    if (d < 0) d += syn
    printf "%.0f\n", d
  }')
  days_to_new=$(awk -v pd="$phase_days" -v syn=29.530588853 'BEGIN {
    printf "%.0f\n", syn - pd
  }')

  printf '%s|%s|%d|%s|%s' \
    "${glyphs[$phase_idx]}" "${names[$phase_idx]}" "$illum" "$days_to_full" "$days_to_new"
}

# ── Hex time ──────────────────────────────────────────────

_hex() {
  local h m s hh mm ss
  h=$(_date +%-H); m=$(_date +%-M); s=$(_date +%-S)
  hh=$(printf "%02X" "$((10#$h))")
  mm=$(printf "%02X" "$((10#$m))")
  ss=$(printf "%02X" "$((10#$s))")

  # One intentional color per hour — swatch gradients into the next hour's color
  # based on minutes elapsed (0 min = this hour's color, 59 min ≈ next hour's color)
  local -a HOUR_COLORS=(
    "0d1b2a" "1b2838" "1e1b4b" "2d1b69"  # 0–3  : deep night
    "1d4ed8" "dc2626" "ea580c" "f59e0b"  # 4–7  : blue → red → orange → amber
    "84cc16" "22c55e" "14b8a6" "06b6d4"  # 8–11 : lime → green → teal → cyan
    "e0f2fe" "fde68a" "fbbf24" "f97316"  # 12–15: near-white → gold → orange
    "ef4444" "a855f7" "ec4899" "f43f5e"  # 16–19: red → purple → pink → rose
    "7c3aed" "4f46e5" "1d4ed8" "0c1445"  # 20–23: violet → indigo → blue → deep night
  )

  local col_a="${HOUR_COLORS[$h]}"
  local col_b="${HOUR_COLORS[$(( (h + 1) % 24 ))]}"

  local ra=$(( 16#${col_a:0:2} )) ga=$(( 16#${col_a:2:2} )) ba=$(( 16#${col_a:4:2} ))
  local rb=$(( 16#${col_b:0:2} )) gb=$(( 16#${col_b:2:2} )) bb=$(( 16#${col_b:4:2} ))

  local sr=$(( (ra * (60 - m) + rb * m) / 60 ))
  local sg=$(( (ga * (60 - m) + gb * m) / 60 ))
  local sb=$(( (ba * (60 - m) + bb * m) / 60 ))

  local swatch_hex; swatch_hex=$(printf "%02x%02x%02x" "$sr" "$sg" "$sb")

  local brk="$SUBTLE" c1="$IRIS" c2="$FOAM" c3="$GOLD"
  local swatch="<span foreground=\"#${swatch_hex}\">■</span>"

  echo "<span foreground=\"${brk}\">{</span>${swatch}<span foreground=\"${brk}\">}</span> <span foreground=\"${brk}\">{</span><span foreground=\"${c1}\">${hh}</span><span foreground=\"${brk}\">}{</span><span foreground=\"${c2}\">${mm}</span><span foreground=\"${brk}\">}{</span><span foreground=\"${c3}\">${ss}</span><span foreground=\"${brk}\">}</span>"
}

# ── Day progress ──────────────────────────────────────────

_progress() {
  local ep; ep="$(_now)"
  local h m s
  h=$(date -d "@$ep" +%-H)
  m=$(date -d "@$ep" +%-M)
  s=$(date -d "@$ep" +%-S)

  local secs=$(( h * 3600 + m * 60 + s ))
  local pct=$(( secs * 100 / 86400 ))
  local filled=$(( secs * 10 / 86400 ))

  local c_fill="$FOAM" c_empty="$MUTED" c_pct="$GOLD"
  local bar="" i
  for (( i = 0;      i < filled; i++ )); do bar+="<span foreground=\"${c_fill}\">█</span>"; done
  for (( i = filled; i < 10;     i++ )); do bar+="<span foreground=\"${c_empty}\">░</span>"; done

  printf "%s <span foreground=\"${c_pct}\">%d%%</span>  %s" "$bar" "$pct" "$(_fmt "$ep")"
}

# ── Caliper clock ────────────────────────────────────────

_caliper() {
  local ep; ep="$(_now)"
  local h; h=$(_date -d "@$ep" +%-H)
  local is_pm=$(( h >= 12 ? 1 : 0 ))
  local dist=$(( h > 12 ? h - 12 : 12 - h ))
  local level=$(( 12 - dist ))
  local arm_len=$(( (level * 10 + 6) / 12 ))

  local a="" i
  for (( i = 0; i < arm_len; i++ )); do a+="━"; done

  local -a am_objects=( "A speck" "A mite" "A poppy" "A sesame" "A lentil" "A kernel" "A corn pop" "A blueberry" "A chestnut" "A sugar cube" "A small cork" "A Matchbox car" "A film canister" )
  local -a pm_objects=( "A ghost" "A mote" "A spore" "A grain" "A fleck" "A bead" "A BB" "A pill" "A die" "A thimble" "A pocket watch" "A lighter" "A harmonica" )

  local obj
  if [[ $is_pm -eq 1 ]]; then
    obj="${pm_objects[$level]}"
  else
    obj="${am_objects[$level]}"
  fi

  local jaw
  if [[ $arm_len -gt 0 ]]; then
    jaw="${a}┤ ${obj} ├${a}"
  else
    jaw="┤${obj}├"
  fi

  printf "%s  %s" "$jaw" "$(_fmt "$ep")"
}

# ── Natural language time ─────────────────────────────────

_natural() {
  local ep; ep="$(_now)"
  local h m
  h=$(_date -d "@$ep" +%-H)
  m=$(_date -d "@$ep" +%-M)

  # Round to nearest 5 minutes
  local r=$(( (m + 2) / 5 * 5 ))
  if [[ $r -eq 60 ]]; then r=0; h=$(( (h + 1) % 24 )); fi

  # Index 0–23 maps cleanly: midnight=0, noon=12
  local -a hour_names=(
    "midnight" "one"   "two"   "three" "four"  "five"
    "six"      "seven" "eight" "nine"  "ten"   "eleven"
    "noon"     "one"   "two"   "three" "four"  "five"
    "six"      "seven" "eight" "nine"  "ten"   "eleven"
  )
  local next_h=$(( (h + 1) % 24 ))

  if [[ $r -eq 0 ]]; then
    if [[ $h -eq 0 || $h -eq 12 ]]; then
      echo "${hour_names[$h]}"
    else
      echo "${hour_names[$h]} o'clock"
    fi
  elif [[ $r -le 30 ]]; then
    local -a past_words=( "" "five past" "ten past" "quarter past"
                             "twenty past" "twenty-five past" "half past" )
    echo "${past_words[$(( r / 5 ))]} ${hour_names[$h]}"
  else
    local -a to_words=( "" "five to" "ten to" "quarter to" "twenty to" "twenty-five to" )
    echo "${to_words[$(( (60 - r) / 5 ))]} ${hour_names[$next_h]}"
  fi
}

# ── Commands ──────────────────────────────────────────────

cmd="${1:-show}"
case "$cmd" in
  next)
    _next_mode
    exit 0 ;;
  toggle)
    [[ "$CLOCK_24H" == "1" ]] && echo "0" > "$H24_FILE" || echo "1" > "$H24_FILE"
    exit 0 ;;
  help|-h|--help)
    echo "Quantum Clock v3  modes: ${CLOCK_MODES[*]}"
    exit 0 ;;
esac

# ── Mode selection ────────────────────────────────────────

mode=$(_current_mode)

# Hourly surprise: only fires when idling in the default mode,
# shows a random non-default mode for a ~5-second window.
if [[ "$mode" == "$CLOCK_DEFAULT" ]]; then
  _min=$(date +%-M); _sec=$(date +%-S)
  if [[ $_min -eq 0 && $_sec -lt 5 ]]; then
    stamp=$(date +%Y%m%d%H)
    if [[ ! -f "$HOURLY_FILE" || "$(cat "$HOURLY_FILE")" != "$stamp" ]]; then
      echo "$stamp" > "$HOURLY_FILE"
      surprise_pool=()
      for _m in "${CLOCK_MODES[@]}"; do
        [[ "$_m" != "$CLOCK_DEFAULT" ]] && surprise_pool+=("$_m")
      done
      [[ ${#surprise_pool[@]} -gt 0 ]] && mode="${surprise_pool[$((RANDOM % ${#surprise_pool[@]}))]}"
    fi
  fi
fi

# ── Render ────────────────────────────────────────────────

ep="$(_now)"
base_tip="$(_tooltip_base "$ep")"
class="$mode"

case "$mode" in
  moon)
    IFS='|' read -r glyph name illum days_to_full days_to_new <<< "$(_lunar)"
    if   (( illum < 25 )); then illum_color="$MUTED"
    elif (( illum < 50 )); then illum_color="$SUBTLE"
    elif (( illum < 75 )); then illum_color="$FOAM"
    else                        illum_color="$GOLD"
    fi
    text="<span foreground=\"${IRIS}\">${glyph}</span> $(_fmt "$ep")"
    tip="<span foreground='${IRIS}'>${name}</span> · <span foreground='${illum_color}'>${illum}%</span> illuminated\n<span foreground='${FOAM}'>${days_to_full}d</span> <span foreground='${SUBTLE}'>to full moon</span>  ·  <span foreground='${SUBTLE}'>${days_to_new}d to new moon</span>\n\n${base_tip}"
    ;;
  hex)
    text="󰅩 $(_hex)"
    tip="<span foreground='${IRIS}'>Hexadecimal time</span>\n\n${base_tip}"
    ;;
  progress)
    text="$(_progress)"
    tip="<span foreground='${FOAM}'>Day progress</span>\n\n${base_tip}"
    ;;
  natural)
    text="<span foreground=\"${SUBTLE}\">$(_natural)</span>"
    tip="<span foreground='${SUBTLE}'>Natural time</span>\n\n${base_tip}"
    ;;
  caliper)
    text="$(_caliper)"
    tip="<span foreground='${ROSE}'>Caliper clock</span>\n\n${base_tip}"
    ;;
  *)
    text="$(_fmt "$ep")"
    tip="$base_tip"
    ;;
esac

_wrap_json "$text" "$tip" "$class"
