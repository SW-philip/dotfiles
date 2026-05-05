#!/usr/bin/env bash
# Interactive volume control — runs inside the ghostty popup.
# j/↓: vol down   k/↑: vol up   m: mute toggle   q: quit

SINK="@DEFAULT_AUDIO_SINK@"

trap 'tput rmcup; tput cnorm; exit' INT TERM EXIT
tput smcup
tput civis

draw() {
    local raw vol muted bar filled i

    raw=$(wpctl get-volume "$SINK" 2>/dev/null)
    vol=$(awk '{printf "%d", $2*100}' <<< "$raw")
    muted=$(grep -q MUTED <<< "$raw" && echo "  [MUTED]" || echo "")

    filled=$(( vol / 5 ))
    bar=""
    for (( i = 0; i < 20; i++ )); do
        (( i < filled )) && bar+="█" || bar+="░"
    done

    tput clear
    printf "\n"
    printf "   Volume: %d%%%s\n\n" "$vol" "$muted"
    printf "   %s\n\n" "$bar"
    printf "   ↑/k  vol+     ↓/j  vol-     m  mute     q  quit\n"
}

while true; do
    draw

    IFS= read -r -s -n1 -t 0.5 key || continue

    # Arrow key escape sequences
    if [[ "$key" == $'\x1b' ]]; then
        IFS= read -r -s -n1 -t 0.05 s1 || continue
        IFS= read -r -s -n1 -t 0.05 s2 || continue
        case "${s1}${s2}" in
            '[A') wpctl set-volume "$SINK" 5%+ ;;
            '[B') wpctl set-volume "$SINK" 5%- ;;
        esac
    else
        case "$key" in
            k) wpctl set-volume "$SINK" 5%+ ;;
            j) wpctl set-volume "$SINK" 5%- ;;
            m) wpctl set-mute   "$SINK" toggle ;;
            q) break ;;
        esac
    fi

    pkill -RTMIN+1 waybar 2>/dev/null
done
