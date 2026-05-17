#!/usr/bin/env bash
# health-check.sh — system health audit for NixOS
# run as normal user (will sudo where needed)

set -uo pipefail

HOST=$(hostname)
IS_SURFACE=false; IS_DESKTOP=false
[[ "$HOST" == "surface" ]] && IS_SURFACE=true
[[ "$HOST" == "desktop"   ]] && IS_DESKTOP=true

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

# Sample CPU before any work; delta is computed at end of script
read -r _cpu _user _nice _system _idle _iowait _irq _softirq _steal _ < /proc/stat 2>/dev/null || true

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

luks_count=$(lsblk -o TYPE | grep -c "^crypt$" || true)
if $IS_DESKTOP; then
  if [ "$luks_count" -ge 2 ]; then
    pass "both LUKS devices active ($luks_count crypt devices)"
  elif [ "$luks_count" -eq 1 ]; then
    warn "only 1 LUKS device active — /srv or root drive may not be unlocked"
  else
    fail "no active LUKS devices found"
  fi
else
  if [ "$luks_count" -ge 1 ]; then
    pass "LUKS device active ($luks_count crypt device(s))"
  else
    fail "no active LUKS devices found"
  fi
fi

# Check TPM2 enrollment on all crypto_LUKS partitions
while IFS= read -r raw; do
  part=$(echo "$raw" | tr -d ' └─├─')
  [ -z "$part" ] && continue
  tpm_enrolled=$(sudo systemd-cryptenroll "/dev/$part" 2>/dev/null | grep -c "tpm2" || true)
  if [ "$tpm_enrolled" -gt 0 ]; then
    pass "TPM2 enrolled in /dev/$part"
  else
    warn "TPM2 not enrolled in /dev/$part — run: sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/$part"
  fi
done < <(lsblk -o NAME,TYPE,FSTYPE | awk '$3=="crypto_LUKS"{print $1}')

########################################
echo "── CPU & Thermals"
########################################

# Use /proc/stat for reliable idle %
# CPU idle % is evaluated at end of script using samples taken at start/finish

governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true)
if [ "$governor" = "powersave" ]; then
  pass "CPU governor: powersave (intel_pstate + HWP active)"
elif [ -n "$governor" ]; then
  warn "CPU governor: $governor — expected powersave; EPP writes may be broken"
else
  warn "could not read CPU governor"
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
echo "── GPU"
########################################

if $IS_DESKTOP; then
  nvidia_mod=$(lsmod 2>/dev/null | grep -c "^nvidia " || true)
  if [ "$nvidia_mod" -gt 0 ]; then
    pass "nvidia kernel module loaded"
  else
    fail "nvidia module not loaded — check: lsmod | grep nvidia"
  fi

  if command -v nvidia-smi &>/dev/null; then
    gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ' || true)
    if [ -n "$gpu_temp" ] && [[ "$gpu_temp" =~ ^[0-9]+$ ]]; then
      if [ "$gpu_temp" -le 50 ]; then
        pass "GPU temp OK at ${gpu_temp}°C idle"
      elif [ "$gpu_temp" -le 70 ]; then
        warn "GPU temp elevated at ${gpu_temp}°C idle"
      else
        fail "GPU temp high at ${gpu_temp}°C idle"
      fi
    else
      warn "nvidia-smi available but no temp returned"
    fi
  else
    warn "nvidia-smi not available — add linuxPackages.nvidia_x11 tools to PATH"
  fi
else
  # Surface: Intel GPU — xe (Iris Xe, newer) or i915 (legacy); both may coexist
  if lsmod 2>/dev/null | grep -qE "^(xe|i915)\s"; then
    loaded=$(lsmod 2>/dev/null | awk '/^(xe|i915)\s/{printf "%s ", $1}' | sed 's/ $//')
    pass "Intel GPU module(s) loaded: $loaded"
  else
    warn "no Intel GPU module (xe/i915) loaded — check: lsmod | grep -E 'xe|i915'"
  fi
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
  devs=(/dev/nvme0n1)
  $IS_DESKTOP && devs+=(/dev/sda /dev/sdb)
  for dev in "${devs[@]}"; do
    [ -e "$dev" ] || continue
    h=$(sudo smartctl -H "$dev" 2>/dev/null | grep -i "overall\|result" | head -1 || true)
    if echo "$h" | grep -qi "PASSED\|OK"; then
      pass "$dev health: $h"
    elif [ -n "$h" ]; then
      fail "$dev health: $h"
    else
      warn "$dev: smartctl returned no health data"
    fi
  done
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

if $IS_DESKTOP; then
  if mountpoint -q /srv 2>/dev/null; then
    srv_pct=$(df /srv | awk 'NR==2{print $5}' | tr -d '%')
    if [ "$srv_pct" -le 80 ]; then
      pass "/srv ${srv_pct}% full"
    elif [ "$srv_pct" -le 92 ]; then
      warn "/srv ${srv_pct}% full — media drive filling up"
    else
      fail "/srv ${srv_pct}% full — running low on media storage"
    fi
  else
    fail "/srv not mounted — second LUKS drive may not have unlocked"
  fi
fi

if mountpoint -q /mnt/backup 2>/dev/null; then
  bak_pct=$(df /mnt/backup | awk 'NR==2{print $5}' | tr -d '%')
  pass "/mnt/backup mounted (${bak_pct}% full)"
else
  warn "/mnt/backup not mounted (nofail — may be expected if drive is off)"
fi

########################################
echo "── btrfs Device Errors"
########################################

btrfs_mps=(/)
$IS_DESKTOP && btrfs_mps+=(/srv)
for mp in "${btrfs_mps[@]}"; do
  if mountpoint -q "$mp" 2>/dev/null; then
    errors=$(sudo btrfs device stats "$mp" 2>/dev/null | awk '{sum += $2} END {print sum+0}')
    if [ "$errors" -eq 0 ]; then
      pass "btrfs $mp: no device errors"
    else
      fail "btrfs $mp: $errors error(s) — check: sudo btrfs device stats $mp"
    fi
  fi
done

########################################
echo "── Battery"
########################################

bat_path=$(upower -e 2>/dev/null | grep -i battery | head -1 || true)
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
  # upower fallback: read directly from sysfs (works without upowerd)
  bat_sysfs=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1 || true)
  if [ -n "$bat_sysfs" ]; then
    percentage=$(cat "$bat_sysfs/capacity" 2>/dev/null || true)
    state=$(cat "$bat_sysfs/status" 2>/dev/null || true)
    charge_full=$(cat "$bat_sysfs/charge_full" "$bat_sysfs/energy_full" 2>/dev/null | head -1 || true)
    charge_design=$(cat "$bat_sysfs/charge_full_design" "$bat_sysfs/energy_full_design" 2>/dev/null | head -1 || true)

    if [ -n "$charge_full" ] && [ -n "$charge_design" ] && [ "$charge_design" -gt 0 ]; then
      cap_int=$(( charge_full * 100 / charge_design ))
      if [ "$cap_int" -ge 80 ]; then
        pass "battery health ${cap_int}% capacity"
      elif [ "$cap_int" -ge 60 ]; then
        warn "battery health ${cap_int}% — degraded"
      else
        fail "battery health ${cap_int}% — significantly degraded"
      fi
    fi

    [ -n "$state" ] && [ -n "$percentage" ] && pass "battery state: $state at ${percentage}%"
  elif $IS_DESKTOP; then
    pass "no battery (desktop)"
  else
    warn "no battery detected — check: ls /sys/class/power_supply/"
  fi
fi

########################################
echo "── Network / VPN"
########################################

if ip link show protonvpn &>/dev/null; then
  pass "WireGuard protonvpn interface up"
else
  warn "WireGuard protonvpn interface not found (VPN may be intentionally off)"
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

# common services
services=(
  "NetworkManager"
  "sshd"
  "bluetooth"
  "pipewire"
)
# desktop-only services
if $IS_DESKTOP; then
  services+=("smartd" "iptv-serve")
fi

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
echo "── CPU Idle (measured over script runtime)"
########################################

if [ -n "${_idle:-}" ]; then
  read -r _ u2 n2 s2 i2 w2 r2 f2 t2 _ < /proc/stat 2>/dev/null || true
  _dtotal=$(( (u2+n2+s2+i2+w2+r2+f2+t2) - (_user+_nice+_system+_idle+_iowait+_irq+_softirq+_steal) ))
  _didle=$(( i2 - _idle ))
  _idle_pct=$(( 100 * _didle / _dtotal ))
  if [ "$_idle_pct" -ge 60 ]; then
    pass "CPU idle at ${_idle_pct}% (over script runtime)"
  elif [ "$_idle_pct" -ge 20 ]; then
    warn "CPU idle at ${_idle_pct}% — somewhat busy at rest"
  else
    fail "CPU idle at ${_idle_pct}% — high load at rest"
  fi
else
  warn "could not read CPU idle from /proc/stat"
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
