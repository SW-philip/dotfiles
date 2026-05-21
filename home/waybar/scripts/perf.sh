#!/usr/bin/env bash
# CPU utilization % + memory usage for the waybar perf widget.
# CPU% is computed from /proc/stat delta between runs (cached in XDG_RUNTIME_DIR).
# No root or sudo required.
set -euo pipefail

# shellcheck source=/dev/null
source "$HOME/.config/waybar/palette.sh"

# ── CPU utilization ───────────────────────────────────────────────
CACHE="${XDG_RUNTIME_DIR:-/tmp}/waybar_perf_cpu"
read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat

if [[ -f "$CACHE" ]]; then
    read -r p_user p_nice p_system p_idle p_iowait p_irq p_softirq p_steal < "$CACHE"
    prev_idle=$(( p_idle  + p_iowait ))
    curr_idle=$(( idle    + iowait   ))
    prev_total=$(( p_user + p_nice + p_system + p_idle + p_iowait + p_irq + p_softirq + p_steal ))
    curr_total=$((  user  +  nice  +  system  +  idle  +  iowait  +  irq  +  softirq  +  steal  ))
    d_idle=$(( curr_idle  - prev_idle  ))
    d_total=$(( curr_total - prev_total ))
    cpu_pct=$(( d_total > 0 ? (d_total - d_idle) * 100 / d_total : 0 ))
else
    cpu_pct=0
fi
echo "$user $nice $system $idle $iowait $irq $softirq $steal" > "$CACHE"

# ── Memory ────────────────────────────────────────────────────────
mem_total=$(awk '/^MemTotal:/     { print $2 }' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
mem_used=$(( mem_total - mem_avail ))
mem_pct=$(( mem_used * 100 / mem_total ))
mem_used_g=$(awk "BEGIN { printf \"%.1f\", $mem_used  / 1048576 }")
mem_total_g=$(awk "BEGIN { printf \"%.1f\", $mem_total / 1048576 }")

# ── Colour thresholds ─────────────────────────────────────────────
if   (( cpu_pct >= 90 )); then CPU_COLOR="$LOVE";   cpu_state="critical"
elif (( cpu_pct >= 70 )); then CPU_COLOR="$GOLD";   cpu_state="warn"
elif (( cpu_pct >= 40 )); then CPU_COLOR="$TEXT";   cpu_state="active"
else                           CPU_COLOR="$SUBTLE";  cpu_state="idle"
fi

if   (( mem_pct >= 90 )); then MEM_COLOR="$LOVE"
elif (( mem_pct >= 70 )); then MEM_COLOR="$GOLD"
else                           MEM_COLOR="$FOAM"
fi

SNARK_FILE="$HOME/.config/waybar/snark.json"

TEXT="󰻠 ${cpu_pct}%  󰍛 ${mem_pct}%"
TOOLTIP=$(printf \
    "<span foreground='${SUBTLE}'>CPU:</span>  <span foreground='${CPU_COLOR}'>%d%%</span>\n<span foreground='${SUBTLE}'>RAM:</span>  <span foreground='${MEM_COLOR}'>%s / %s GiB</span>  <span foreground='${SUBTLE}'>(%d%%)</span>" \
    "$cpu_pct" "$mem_used_g" "$mem_total_g" "$mem_pct")

if [[ -f "$SNARK_FILE" ]] && command -v jq >/dev/null; then
    _snark=$(jq -r ".perf.${cpu_state}[]?" "$SNARK_FILE" 2>/dev/null | shuf -n1 || true)
    [[ -n "$_snark" && "$_snark" != "null" ]] && \
        TOOLTIP+=$'\n'"<span foreground='${SUBTLE}'>────────────────────</span>"$'\n'"<span foreground='${IRIS}'>$_snark</span>"
fi

jq -nc \
    --arg text    "$TEXT" \
    --arg tooltip "$TOOLTIP" \
    --arg class   "$cpu_state" \
    '{text:$text, tooltip:$tooltip, class:$class}'
