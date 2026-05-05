#!/usr/bin/env bash
# grade-redundancy.sh — NixOS config duplication & redundancy auditor
# run from your nixos flake root

set -uo pipefail

ROOT="${1:-$HOME/nixos}"
cd "$ROOT"

PASS=0
WARN=0
FAIL=0

pass() { echo "  ✔ $1"; ((PASS++)); }
warn() { echo "  ~ $1"; ((WARN++)); }
fail() { echo "  ✗ $1"; ((FAIL++)); }

# Patterns
GENERATED="hardware-configuration\.nix"
FIREWALL_OK="protonvpn\.nix|streaming\.nix"
# Nix internals to exclude from package checks
PKG_SKIP="bash|coreutils|gawk|zsh|stdenv|lib|system|mkShell|callPackage|fetchurl|fetchgit|writeShellScriptBin|override|overrideAttrs|hostPlatform|python3|python312|mkDerivation|runCommand"

echo "nixos redundancy audit"
echo "run from: $ROOT"
echo "date:     $(date)"
echo

########################################
echo "── Duplicate option definitions"
########################################
# Logic:
#   - auto-generated files are excluded from blame
#   - modules that extend firewall rules are excluded from firewall check
#   - profiles/ defining an option is canonical — only fail if
#     multiple non-profile host/module files also set it independently

check_opt() {
  local opt="$1"
  local exclude_pat="${2:-__NOMATCH__}"

  local all
  all=$(grep -rl "$opt" --include="*.nix" . 2>/dev/null \
    | grep -v "flake\.lock" \
    | grep -vE "$GENERATED" \
    | grep -vE "$exclude_pat" \
    | sort || true)

  local profiles host_files host_count
  profiles=$(echo "$all" | grep -E "^./profiles/" || true)
  host_files=$(echo "$all" | grep -vE "^./profiles/" | grep "\.nix$" || true)
  host_count=$(echo "$host_files" | grep -c "\.nix$" || true)

  if [ "$host_count" -gt 1 ]; then
    fail "\"$opt\" set in $host_count non-profile files — real duplication:"
    echo "$host_files" | while read -r f; do [ -n "$f" ] && echo "       $f"; done
  elif [ "$host_count" -eq 1 ] && [ -n "$(echo "$profiles" | grep "\.nix" || true)" ]; then
    warn "\"$opt\" in profile AND $host_files — may be unnecessary override"
  else
    pass "\"$opt\" — clean"
  fi
}

check_opt "time.timeZone"
check_opt "networking.networkmanager.enable"
check_opt "programs.zsh.enable"
check_opt "boot.loader.systemd-boot.enable"
check_opt "boot.loader.efi.canTouchEfiVariables"
check_opt "hardware.enableRedistributableFirmware"
check_opt "services.openssh"
check_opt "networking.firewall" "$FIREWALL_OK"
check_opt "i18n.defaultLocale"
check_opt "nix.settings"
check_opt "nix.gc"

echo
########################################
echo "── Duplicate package declarations"
########################################
# Extract whole-word package names from systemPackages/home.packages blocks
# Track which distinct FILES each package appears in
# Warn at 2 files, fail at 3+

declare -A pkg_seen  # pkg -> "file1|file2|..."

while IFS= read -r nixfile; do
  # Extract package names: whole words after "pkgs." not followed by more dots (avoid pkgs.lib.x etc)
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    # Skip internals
    echo "$pkg" | grep -qE "^($PKG_SKIP)$" && continue
    # Skip short/generic names that cause false positives
    [ ${#pkg} -le 2 ] && continue

    current="${pkg_seen[$pkg]:-}"
    if [[ "$current" != *"$nixfile"* ]]; then
      pkg_seen[$pkg]="${current:+$current|}$nixfile"
    fi
  done < <(grep -oP '(?<=pkgs\.)[a-zA-Z][a-zA-Z0-9_-]+(?!\.)' "$nixfile" 2>/dev/null \
    | grep -vE "^($PKG_SKIP)$" || true)
done < <(find . -name "*.nix" -not -path "./.git/*" -not -name "flake.lock")

pkg_dupes=0
for pkg in "${!pkg_seen[@]}"; do
  files="${pkg_seen[$pkg]}"
  count=$(echo "$files" | tr '|' '\n' | grep -c "\.nix" || true)
  if [ "$count" -ge 3 ]; then
    fail "\"$pkg\" declared in $count files — consolidate:"
    echo "$files" | tr '|' '\n' | while read -r f; do [ -n "$f" ] && echo "       $f"; done
    ((pkg_dupes++))
  elif [ "$count" -eq 2 ]; then
    warn "\"$pkg\" in 2 files — intentional split?"
    ((pkg_dupes++))
  fi
done
[ "$pkg_dupes" -eq 0 ] && pass "no duplicate package declarations"

echo
########################################
echo "── Duplicate imports"
########################################
# Profiles imported many times = correct, not flagged
# Non-profile modules imported 3+ times = should be a profile
# Non-profile modules imported exactly 3 times = warning

declare -A imp_count

while IFS= read -r line; do
  # Match relative imports like ../../modules/foo.nix or ./bar.nix
  imp=$(echo "$line" | grep -oP '\.\.?/[\w./]+\.nix' | head -1)
  [ -z "$imp" ] && continue
  # Normalise: strip leading ./
  imp=$(echo "$imp" | sed 's|^\./||')
  imp_count[$imp]=$((${imp_count[$imp]:-0} + 1))
done < <(grep -rh "^\s*\.\." --include="*.nix" . 2>/dev/null || true)

imp_issues=0
for imp in "${!imp_count[@]}"; do
  count="${imp_count[$imp]}"
  is_profile=$(echo "$imp" | grep -c "profiles/" || true)
  if [ "$is_profile" -gt 0 ]; then
    # Profiles are meant to be reused — only flag if absurdly high
    [ "$count" -gt 10 ] && warn "profile \"$imp\" imported $count times — unexpectedly high"
  else
    if [ "$count" -ge 4 ]; then
      fail "\"$imp\" imported $count times — should this be a profile?"
      ((imp_issues++))
    elif [ "$count" -eq 3 ]; then
      warn "\"$imp\" imported 3 times — watch this"
      ((imp_issues++))
    fi
  fi
done
[ "$imp_issues" -eq 0 ] && pass "import structure looks clean"

echo
########################################
echo "── Dead files"
########################################
# Files that exist but aren't imported anywhere
# Excludes: flake.nix, home.nix, hardware-configuration.nix, default.nix

dead=0
while IFS= read -r nixfile; do
  base=$(basename "$nixfile")
  relpath=$(echo "$nixfile" | sed 's|^\./||')

  [[ "$base" == "flake.nix" ]] && continue
  [[ "$base" == "home.nix" ]] && continue
  [[ "$base" == "hardware-configuration.nix" ]] && continue
  [[ "$base" == "default.nix" ]] && continue

  refs=$(grep -rl "$base" --include="*.nix" . 2>/dev/null \
    | grep -v "^\./$relpath$" \
    | grep -v "flake\.lock" \
    | wc -l || true)

  if [ "$refs" -eq 0 ]; then
    fail "\"$relpath\" not imported anywhere — dead file"
    ((dead++))
  fi
done < <(find . -name "*.nix" -not -path "./.git/*" -not -name "flake.lock")

[ "$dead" -eq 0 ] && pass "no dead .nix files"

echo
########################################
echo "── Host files setting profile-level options"
########################################
# These belong in profiles — flag if a host file sets them directly

host_issues=0
for host_file in hosts/*/host.nix hosts/*/default.nix hosts/*/*/host.nix; do
  [ -f "$host_file" ] || continue
  for opt in \
    "time.timeZone" \
    "i18n.defaultLocale" \
    "programs.zsh.enable" \
    "nix.settings" \
    "nix.gc" \
    "services.pipewire" \
    "hardware.bluetooth.enable" \
    "fonts.packages"
  do
    if grep -q "$opt" "$host_file" 2>/dev/null; then
      fail "\"$opt\" in $host_file — belongs in a shared profile"
      ((host_issues++))
    fi
  done
done
[ "$host_issues" -eq 0 ] && pass "host files not setting profile-level options"

echo
########################################
echo "── Stale backup files"
########################################

stale_list=$(find . \( -name "*.bak" -o -name "*.old" -o -name "*~" \) \
  -not -path "./.git/*" 2>/dev/null || true)
stale_count=$(echo "$stale_list" | grep -c "\." || true)

if [ "$stale_count" -gt 0 ]; then
  fail "$stale_count stale backup file(s) found:"
  echo "$stale_list" | while read -r f; do [ -n "$f" ] && echo "       $f"; done
else
  pass "no stale backup files"
fi

echo
########################################
echo "── environment variable style"
########################################
# Both sessionVariables and variables in use = pick one

sv=$(grep -rl "environment\.sessionVariables" --include="*.nix" . 2>/dev/null \
  | grep -v "flake\.lock" | grep -c "\.nix" || true)
ev=$(grep -rl "environment\.variables" --include="*.nix" . 2>/dev/null \
  | grep -v "flake\.lock" | grep -c "\.nix" || true)

if [ "$sv" -gt 0 ] && [ "$ev" -gt 0 ]; then
  sv_files=$(grep -rl "environment\.sessionVariables" --include="*.nix" . 2>/dev/null | grep -v "flake\.lock" | tr '\n' ' ')
  ev_files=$(grep -rl "environment\.variables" --include="*.nix" . 2>/dev/null | grep -v "flake\.lock" | tr '\n' ' ')
  warn "mixed environment.sessionVariables ($sv files) and environment.variables ($ev files)"
  echo "       sessionVariables: $sv_files"
  echo "       variables:        $ev_files"
else
  pass "consistent environment variable style"
fi

echo
########################################
echo "── Hardcoded usernames in shared modules/profiles"
########################################
# Host files are exempt — shared modules/profiles should not hardcode usernames

hardcoded=0
while IFS= read -r match; do
  file=$(echo "$match" | cut -d: -f1)
  echo "$file" | grep -qE "^./hosts/" && continue
  echo "$file" | grep -qE "$GENERATED" && continue
  fail "hardcoded username in \"$file\" — use a variable"
  ((hardcoded++))
done < <(grep -rn '"prepko"\|/home/prepko' --include="*.nix" . 2>/dev/null \
  | grep -v "flake\.lock" | grep -v "^#" || true)
[ "$hardcoded" -eq 0 ] && pass "no hardcoded usernames in shared modules"

echo
########################################
echo "── Secrets hygiene"
########################################
# Flag hardcoded VPN/secret paths in non-host files
# Flag any plaintext passwords

secret_issues=0
while IFS= read -r match; do
  file=$(echo "$match" | cut -d: -f1)
  echo "$file" | grep -qE "$GENERATED" && continue
  warn "hardcoded secret path in \"$file\" — use sops"
  ((secret_issues++))
done < <(grep -rn '\.conf"\|\.key"\|password.*=.*"[^"]' --include="*.nix" . 2>/dev/null \
  | grep -viE "allowedTCPPorts|allowedUDPPorts|openFirewall|description|comment|#" \
  | grep -v "flake\.lock" || true)
[ "$secret_issues" -eq 0 ] && pass "no obvious hardcoded secrets"

echo
########################################
# Scoring
########################################

TOTAL=$((PASS + WARN + FAIL))
[ "$TOTAL" -eq 0 ] && TOTAL=1

# Fails cost full points, warns cost 40%, passes score full
SCORE=$(( (PASS * 100 + WARN * 60) / TOTAL ))

echo "────────────────────────────────"
echo "Results: $TOTAL checks"
echo "  ✔ passed: $PASS"
echo "  ~ warned: $WARN"
echo "  ✗ failed: $FAIL"
echo

if [ "$SCORE" -ge 93 ]; then
  GRADE="A"; MSG="excellent — very clean config"
elif [ "$SCORE" -ge 83 ]; then
  GRADE="B"; MSG="good, minor issues to address"
elif [ "$SCORE" -ge 72 ]; then
  GRADE="C"; MSG="moderate duplication, worth a cleanup pass"
elif [ "$SCORE" -ge 60 ]; then
  GRADE="D"; MSG="significant redundancy — refactor recommended"
else
  GRADE="F"; MSG="major duplication — needs real work"
fi

echo "Grade: $GRADE ($SCORE/100) — $MSG"
