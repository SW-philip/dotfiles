#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "$HOME/.config/waybar/palette.sh"

# ── Main disk (/) ──────────────────────────────────────────────────
read -r used avail pct < <(df -h / | awk 'NR==2{ gsub(/%/,"",$5); print $3,$4,$5 }')

# btrfs allocation detail from sysfs — no root required
uuid=$(ls /sys/fs/btrfs/ 2>/dev/null | head -1)
data_used_g=""; data_total_g=""; meta_used_g=""
if [[ -n "$uuid" ]]; then
    base="/sys/fs/btrfs/$uuid/allocation"
    du_raw=$(cat "$base/data/disk_used"        2>/dev/null || true)
    dt_raw=$(cat "$base/data/disk_total_bytes"  2>/dev/null || true)
    mu_raw=$(cat "$base/metadata/disk_used"     2>/dev/null || true)
    if [[ -n "$du_raw" && -n "$dt_raw" ]]; then
        data_used_g=$(awk "BEGIN{printf \"%.1f\", $du_raw/1073741824}")
        data_total_g=$(awk "BEGIN{printf \"%.1f\", $dt_raw/1073741824}")
        meta_used_g=$(awk "BEGIN{printf \"%.1f\", ${mu_raw:-0}/1073741824}")
    fi
fi

# ── NixOS Generations ─────────────────────────────────────────────
gen_total=$(ls -d /nix/var/nix/profiles/system-*-link 2>/dev/null | wc -l)
current_gen=$(readlink /nix/var/nix/profiles/system 2>/dev/null \
    | grep -oP '(?<=system-)\d+(?=-link)' || echo "?")

# ── btrfs Snapshots ───────────────────────────────────────────────
snap_count="n/a"
if command -v btrfs &>/dev/null; then
    n=$(btrfs subvolume list / 2>/dev/null | grep -ci snap || true)
    [[ -n "$n" ]] && snap_count="$n"
fi
# Fallback: count entries in /.snapshots (snapper layout)
if [[ "$snap_count" == "n/a" || "$snap_count" == "0" ]] && [[ -d "/.snapshots" ]]; then
    snap_count=$(ls -1 /.snapshots 2>/dev/null | wc -l)
fi

# ── Backup SSD (/mnt/backup) ──────────────────────────────────────
backup_used=""; backup_avail=""; backup_pct=0
if mountpoint -q /mnt/backup 2>/dev/null; then
    read -r backup_used backup_avail backup_pct < <(
        df -h /mnt/backup | awk 'NR==2{ gsub(/%/,"",$5); print $3,$4,$5 }'
    )
fi

# ── State / colour ────────────────────────────────────────────────
if   (( pct >= 90 )); then state="critical"; COLOR="$LOVE"
elif (( pct >= 75 )); then state="warn";     COLOR="$GOLD"
elif (( pct >= 50 )); then state="ok";       COLOR="$TEXT"
else                       state="fresh";    COLOR="$FOAM"
fi

BAR_TEXT="󰋊 ${pct}%"

# ── Tooltip ───────────────────────────────────────────────────────
NL=$'\n'
TT="<span foreground='${IRIS}'><b>󰋊 btrfs /</b></span>${NL}"
TT+="<span foreground='${SUBTLE}'>Used:</span>  <span foreground='${COLOR}'>$used</span>  "
TT+="<span foreground='${SUBTLE}'>Free:</span> <span foreground='${FOAM}'>$avail</span>${NL}"

if [[ -n "$data_used_g" ]]; then
    TT+="<span foreground='${SUBTLE}'>Data:</span>  <span foreground='${SUBTLE}'>$data_used_g G / $data_total_g G</span>${NL}"
    TT+="<span foreground='${SUBTLE}'>Meta:</span>  <span foreground='${SUBTLE}'>$meta_used_g G used</span>${NL}"
fi

TT+="${NL}"
TT+="<span foreground='${SUBTLE}'>Generation:</span>  "
TT+="<span foreground='${TEXT}'>$current_gen</span>"
TT+=" <span foreground='${SUBTLE}'>($gen_total total)</span>${NL}"
TT+="<span foreground='${SUBTLE}'>Snapshots:</span>   "
TT+="<span foreground='${TEXT}'>$snap_count</span>"

if [[ -n "$backup_used" ]]; then
    if   (( backup_pct >= 90 )); then BCOL="$LOVE"
    elif (( backup_pct >= 75 )); then BCOL="$GOLD"
    else                              BCOL="$FOAM"
    fi
    TT+="${NL}${NL}<span foreground='${IRIS}'><b>󰋊 /mnt/backup</b></span>${NL}"
    TT+="<span foreground='${SUBTLE}'>Used:</span>  <span foreground='${BCOL}'>$backup_used</span>  "
    TT+="<span foreground='${SUBTLE}'>Free:</span> <span foreground='${FOAM}'>$backup_avail</span>"
fi

jq -nc \
    --arg text    "$BAR_TEXT" \
    --arg tooltip "$TT" \
    --arg class   "$state" \
    '{text:$text, tooltip:$tooltip, class:$class}'
