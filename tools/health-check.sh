#!/usr/bin/env bash
# health-check.sh — system health audit for NixOS
# run as normal user (will sudo where needed)

set -uo pipefail

PASS=0
WARN=0
FAIL=0

pass() { echo "  ✔ $1"; ((PASS++)); }
warn() { echo "  ~ $1"; ((WARN++)); }
fail() { echo "  ✗ $1"; ((FAIL++)); }

echo "system health check"
echo "host:  $(hostname)"
echo "date:  $(date)"
echo "user:  $(whoami)"
echo

########################################
echo "── Secure Boot"
########################################

sb=$(bootctl status 2>/dev/null | grep -i "secure boot" | head -1)
if echo "$sb" | grep -qi "enabled"; then
  pass "Secure Boot enabled"
elif echo "$sb" | grep -qi "disabled"; then
  fail "Secure Boot disabled — enable in UEFI firmware"
else
  warn "Secure Boot status unknown: $sb"
fi

# lanzaboote shows up as the boot binary, check for signed stub
if { bootctl status 2>/dev/null || true; } | grep -qi "lanzastub"; then
  pass "lanzaboote (lanzastub) detected"
elif sudo ls /boot/EFI/Linux/*.efi 2>/dev/null | grep -q "."; then
  pass "lanzaboote unified kernel images found in /boot/EFI/Linux"
else
  warn "lanzaboote not confirmed — check: ls /boot/EFI/Linux/"
fi

########################################
echo "── TPM2 / LUKS"
########################################

# Reliable: check for TPM device nodes directly
if [ -e /dev/tpm0 ] || [ -e /dev/tpmrm0 ]; then
  pass "TPM2 device present ($(ls /dev/tpm* 2>/dev/null | tr '\n' ' '))"
else
  fail "no TPM2 device found at /dev/tpm0 or /dev/tpmrm0"
fi

luks_dev=$(lsblk -o NAME,TYPE | grep crypt | head -1 | awk '{print $1}' || true)
if [ -n "$luks_dev" ]; then
  pass "LUKS device active: $luks_dev"
else
  fail "no active LUKS device found"
fi

# Check TPM2 slot enrollment
luks_partition=$(lsblk -o NAME,TYPE,FSTYPE | awk '$3=="crypto_LUKS"{print $1}' | head -1 | tr -d '└─')
tpm_enrolled=$(sudo systemd-cryptenroll /dev/$luks_partition 2>/dev/null | grep -c "tpm2" || true)
if [ "$tpm_enrolled" -gt 0 ]; then
  pass "TPM2 slot enrolled in LUKS ($luks_partition)"
else
  warn "TPM2 slot not found in LUKS — run: sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/$luks_partition"
fi

########################################
echo "── CPU & Thermals"
########################################

# Use /proc/stat for reliable idle %
read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat 2>/dev/null || true
if [ -n "${idle:-}" ]; then
  total=$((user + nice + system + idle + iowait + irq + softirq + steal))
  sleep 3
  read -r cpu2 user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 _ < /proc/stat
  total2=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2))
  dtotal=$((total2 - total))
  didle=$((idle2 - idle))
  idle_pct=$((100 * didle / dtotal))
  if [ "$idle_pct" -ge 60 ]; then
    pass "CPU idle at ${idle_pct}%"
  elif [ "$idle_pct" -ge 20 ]; then
    warn "CPU idle at ${idle_pct}% — somewhat busy at rest"
  else
    fail "CPU idle at ${idle_pct}% — high load at rest"
  fi
else
  warn "could not read CPU idle from /proc/stat"
fi

if command -v sensors &>/dev/null; then
  max_temp=$(sensors 2>/dev/null | awk '/^coretemp/,/^$/' | grep -E "^(Package|Core)" | grep -oP '^\S.*?\+\K[0-9]+(?=\.[0-9]°C)' | sort -n | tail -1 || true)
  if [ -n "$max_temp" ]; then
    if [ "$max_temp" -le 55 ]; then
      pass "CPU temp OK at ${max_temp}°C idle"
    elif [ "$max_temp" -le 75 ]; then
      warn "CPU temp elevated at ${max_temp}°C idle"
    else
      fail "CPU temp high at ${max_temp}°C idle — check thermals"
    fi
  else
    warn "sensors installed but no temp data — run: sudo sensors-detect, then add coretemp to boot.kernelModules"
  fi
else
  warn "sensors not installed — add lm_sensors to systemPackages"
fi

########################################
echo "── Memory"
########################################

total=$(free -m | awk '/^Mem:/{print $2}')
used=$(free -m | awk '/^Mem:/{print $3}')
avail=$(free -m | awk '/^Mem:/{print $7}')
pct=$(( used * 100 / total ))

if [ "$pct" -le 40 ]; then
  pass "RAM usage ${pct}% (${used}MB / ${total}MB, ${avail}MB available)"
elif [ "$pct" -le 70 ]; then
  warn "RAM usage ${pct}% (${used}MB / ${total}MB) — moderate"
else
  fail "RAM usage ${pct}% (${used}MB / ${total}MB) — high at idle"
fi

swap=$(free -m | awk '/^Swap:/{print $3}')
if [ "${swap:-0}" -gt 100 ]; then
  warn "swap in use: ${swap}MB — system may be memory-pressured"
else
  pass "no significant swap usage"
fi

########################################
echo "── Disk Health"
########################################

if command -v smartctl &>/dev/null; then
  health=$(sudo smartctl -H /dev/nvme0n1 2>/dev/null | grep -i "overall\|result" | head -1 || true)
  health=$(sudo smartctl -H /dev/sda 2>/dev/null | grep -i "overall\|result" | head -1 || true)
  health2=$(sudo smartctl -H /dev/sdb 2>/dev/null | grep -i "overall\|result" | head -1 || true)
  if echo "$health" | grep -qi "PASSED\|OK"; then
    pass "NVMe health: $health"
  elif [ -n "$health" ]; then
    fail "NVMe health check: $health"
  else
    warn "smartctl returned no health data"
  fi
else
  warn "smartctl not available — add smartmontools to systemPackages"
fi

root_pct=$(df / | awk 'NR==2{print $5}' | tr -d '%')
if [ "$root_pct" -le 70 ]; then
  pass "root filesystem ${root_pct}% full"
elif [ "$root_pct" -le 85 ]; then
  warn "root filesystem ${root_pct}% full"
else
  fail "root filesystem ${root_pct}% full — running low"
fi

boot_pct=$(df /boot | awk 'NR==2{print $5}' | tr -d '%')
if [ "$boot_pct" -le 70 ]; then
  pass "/boot ${boot_pct}% full"
elif [ "$boot_pct" -le 85 ]; then
  warn "/boot ${boot_pct}% full — consider cleaning old generations"
else
  fail "/boot ${boot_pct}% full — clean old boot entries"
fi

########################################
echo "── Battery"
########################################

bat_path=$(upower -e 2>/dev/null | grep battery | head -1 || true)
if [ -n "$bat_path" ]; then
  bat_info=$(upower -i "$bat_path" 2>/dev/null)
  capacity=$(echo "$bat_info" | grep -i "capacity:" | awk '{print $2}' | tr -d '%' || true)
  state=$(echo "$bat_info" | grep -i "state:" | awk '{print $2}' || true)
  percentage=$(echo "$bat_info" | grep -i "percentage:" | awk '{print $2}' | tr -d '%' || true)

  if [ -n "$capacity" ]; then
    cap_int=${capacity%.*}
    if [ "$cap_int" -ge 80 ]; then
      pass "battery health ${capacity}% capacity"
    elif [ "$cap_int" -ge 60 ]; then
      warn "battery health ${capacity}% — degraded"
    else
      fail "battery health ${capacity}% — significantly degraded"
    fi
  fi

  [ -n "$state" ] && [ -n "$percentage" ] && pass "battery state: $state at ${percentage}%"
else
  pass "no battery (desktop)"
fi

########################################
echo "── Network / VPN"
########################################

if ip link show protonvpn &>/dev/null; then
  pass "WireGuard protonvpn interface up"
else
  fail "WireGuard protonvpn interface not found"
fi

exit_ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || true)
if [ -n "$exit_ip" ]; then
  pass "external IP: $exit_ip (verify this is a ProtonVPN IP)"
else
  warn "could not reach ifconfig.me — no internet or VPN blocking"
fi

ping_ms=$(ping -c 1 -W 2 8.8.8.8 2>/dev/null | grep -oP '(?<=time=)[0-9.]+' || true)
if [ -n "$ping_ms" ]; then
  ping_int=${ping_ms%.*}
  if [ "$ping_int" -le 80 ]; then
    pass "network latency ${ping_ms}ms"
  elif [ "$ping_int" -le 200 ]; then
    warn "network latency ${ping_ms}ms — somewhat high (VPN overhead?)"
  else
    fail "network latency ${ping_ms}ms — high"
  fi
else
  fail "no ping response to 8.8.8.8"
fi

########################################
echo "── Key Services"
########################################

services=(
  "NetworkManager"
  "wg-quick-protonvpn"
  "sshd"
  "bluetooth"
  "pipewire"
)

for svc in "${services[@]}"; do
  if systemctl is-active --quiet "$svc" 2>/dev/null || \
     systemctl --user is-active --quiet "$svc" 2>/dev/null; then
    pass "$svc running"
  else
    status=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
    fail "$svc not running (status: $status)"
  fi
done

if systemctl --user is-active --quiet sqlch-daemon 2>/dev/null; then
  pass "sqlch-daemon running"
else
  warn "sqlch-daemon not running — start with: systemctl --user start sqlch-daemon"
fi

########################################
echo "── Nix Store"
########################################

store_size=$(du -sh /nix/store 2>/dev/null | awk '{print $1}' || true)
[ -n "$store_size" ] && pass "nix store size: $store_size"

old_gens=$(sudo nix-env --list-generations --profile /nix/var/nix/profiles/system 2>/dev/null | wc -l || true)
if [ "$old_gens" -le 5 ]; then
  pass "$old_gens system generation(s) — clean"
elif [ "$old_gens" -le 10 ]; then
  warn "$old_gens generations — consider: sudo nix-collect-garbage -d"
else
  fail "$old_gens generations — run: sudo nix-collect-garbage -d"
fi

########################################
echo "── Failed systemd Units"
########################################

failed=$(systemctl --failed --no-legend 2>/dev/null | grep -c "failed" || true)
user_failed=$(systemctl --user --failed --no-legend 2>/dev/null | grep -c "failed" || true)

if [ "$failed" -eq 0 ]; then
  pass "no failed system units"
else
  fail "$failed failed system unit(s):"
  systemctl --failed --no-legend 2>/dev/null | while read -r line; do echo "       $line"; done
fi

if [ "$user_failed" -eq 0 ]; then
  pass "no failed user units"
else
  fail "$user_failed failed user unit(s):"
  systemctl --user --failed --no-legend 2>/dev/null | while read -r line; do echo "       $line"; done
fi

########################################
# Score
########################################

TOTAL=$((PASS + WARN + FAIL))
[ "$TOTAL" -eq 0 ] && TOTAL=1
SCORE=$(( (PASS * 100 + WARN * 60) / TOTAL ))

echo
echo "────────────────────────────────"
echo "Results: $TOTAL checks"
echo "  ✔ passed: $PASS"
echo "  ~ warned: $WARN"
echo "  ✗ failed: $FAIL"
echo

if [ "$SCORE" -ge 93 ]; then
  GRADE="A"; MSG="system is in excellent shape"
elif [ "$SCORE" -ge 83 ]; then
  GRADE="B"; MSG="good — minor issues to address"
elif [ "$SCORE" -ge 72 ]; then
  GRADE="C"; MSG="some issues worth investigating"
elif [ "$SCORE" -ge 60 ]; then
  GRADE="D"; MSG="several problems found"
else
  GRADE="F"; MSG="system needs attention"
fi

echo "Grade: $GRADE ($SCORE/100) — $MSG"
