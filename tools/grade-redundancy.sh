#!/usr/bin/env bash
# grade-redundancy.sh — NixOS config audit with actionable fix suggestions
# Usage: ./tools/grade-redundancy.sh [root] [--fix]
#   --fix   auto-apply safe fixes (delete dead files / stale backups via git rm)

set -uo pipefail

ROOT="."
FIX_MODE=false
for arg in "$@"; do
  [[ "$arg" == "--fix" ]] && FIX_MODE=true
  [[ "$arg" =~ ^(/|\./) ]] && ROOT="$arg"
done
cd "$ROOT"

PASS=0; WARN=0; FAIL=0
declare -a AUTO_FIX=()   # commands safe to run automatically (git rm)
declare -a MANUAL_FIX=() # notes requiring human judgment

if [ -t 1 ]; then
  cR='\033[0;31m'; cY='\033[0;33m'; cG='\033[0;32m'
  cC='\033[0;36m'; cD='\033[2m'; cX='\033[0m'
else
  cR=''; cY=''; cG=''; cC=''; cD=''; cX=''
fi

pass() { printf "  ${cG}✔${cX} %s\n" "$1"; ((PASS++)); }
warn() { printf "  ${cY}~${cX} %s\n" "$1"; ((WARN++)); }
fail() { printf "  ${cR}✗${cX} %s\n" "$1"; ((FAIL++)); }

# Safe to auto-apply — queues a git rm command
fix_rm() {
  printf "    ${cC}→ git rm %s${cX}\n" "$1"
  AUTO_FIX+=("git rm $1")
}

# Printable shell command to run manually
fix_run() {
  printf "    ${cC}→ %s${cX}\n" "$1"
  AUTO_FIX+=("$1")
}

# Human-judgment note — not auto-applied
fix_note() {
  printf "    ${cD}  %s${cX}\n" "$1"
  MANUAL_FIX+=("$1")
}

# Show where to look in a file
fix_grep() {
  local pat="$1"; local file="$2"
  printf "    ${cD}  grep -n '%s' %s${cX}\n" "$pat" "$file"
}

# Patterns
GENERATED="hardware-configuration\.nix"
FIREWALL_OK="protonvpn\.nix|streaming\.nix"

# These are nix stdlib callables, not packages — exclude from package dedup
PKG_SKIP="bash|coreutils|gawk|zsh|stdenv|lib|system|mkShell|callPackage|fetchurl|fetchgit"
PKG_SKIP+="|writeShellScriptBin|writeShellScript|writeText|writeTextFile|writeScript"
PKG_SKIP+="|override|overrideAttrs|hostPlatform|python3|python312|mkDerivation|runCommand"
PKG_SKIP+="|symlinkJoin|makeWrapper|wrapProgram|substituteAll|replaceStrings"

echo "nixos redundancy audit"
echo "run from: $(pwd)"
echo "date:     $(date)"
echo

########################################
echo "── Duplicate option definitions"
########################################

check_opt() {
  local opt="$1"
  local exclude_pat="${2:-__NOMATCH__}"

  # Require assignment operator so reads like `config.boot.kernelPackages.nvidiaPackages.stable`
  # don't false-positive (those don't have = immediately after the option name).
  local all
  all=$(grep -rl "${opt}[[:space:]]*=" --include="*.nix" . 2>/dev/null \
    | grep -v "flake\.lock" \
    | grep -vE "$GENERATED" \
    | grep -vE "$exclude_pat" \
    | sort || true)

  local profiles non_profiles
  profiles=$(echo "$all" | grep -E "^./profiles/" || true)
  non_profiles=$(echo "$all" | grep -vE "^./profiles/" | grep "\.nix$" || true)

  if [ -z "$(echo "$non_profiles" | grep "\.nix" || true)" ] && \
     [ -z "$(echo "$profiles"    | grep "\.nix" || true)" ]; then
    pass "\"$opt\" — clean"
    return
  fi

  # Group non-profile files by host (hosts/X/... → X, everything else → shared).
  # Different hosts each setting the same option is expected — only flag within the same host.
  declare -A _host_bucket=()
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    local _host
    if [[ "$f" =~ ^./hosts/([^/]+)/ ]]; then
      _host="${BASH_REMATCH[1]}"
    else
      _host="shared"
    fi
    _host_bucket[$_host]+="${f}|"
  done <<< "$non_profiles"

  local real_dupes=0
  for _host in "${!_host_bucket[@]}"; do
    local _files _count
    _files="${_host_bucket[$_host]}"
    _count=$(printf '%s' "$_files" | tr '|' '\n' | grep -c "\.nix" || true)
    if [ "$_count" -gt 1 ]; then
      ((real_dupes++))
      fail "\"$opt\" set $_count times within host '$_host' — real duplication:"
      printf '%s' "$_files" | tr '|' '\n' | while read -r f; do [ -n "$f" ] && echo "       $f"; done
      _primary=$(printf '%s' "$_files" | tr '|' '\n' | grep "\.nix" | head -1)
      printf '%s' "$_files" | tr '|' '\n' | grep "\.nix" | tail -n +2 | while read -r f; do
        [ -n "$f" ] && fix_note "Remove \"$opt\" from $f (keep it in $_primary)"
      done
    fi
  done

  if [ "$real_dupes" -eq 0 ]; then
    local _prof_count _host_override_count _shared_overrides
    _prof_count=$(echo "$profiles" | grep -c "\.nix" || true)
    _shared_overrides=$(echo "$non_profiles" | grep -vE "^./hosts/" || true)

    if [ "$_prof_count" -gt 0 ] && [ -n "$(echo "$_shared_overrides" | grep "\.nix" || true)" ]; then
      warn "\"$opt\" in profile AND shared non-host file — may conflict:"
      echo "$_shared_overrides" | while read -r f; do [ -n "$f" ] && echo "       $f"; done
      fix_note "If not intentional, remove \"$opt\" from the shared file"
    else
      pass "\"$opt\" — clean"
    fi
  fi
}

# Boot
check_opt "boot.loader.systemd-boot.enable"
check_opt "boot.loader.efi.canTouchEfiVariables"
check_opt "boot.kernelPackages"

# Locale / time
check_opt "time.timeZone"
check_opt "i18n.defaultLocale"

# Network — check leaf options, not the parent key
check_opt "networking.networkmanager.enable"
check_opt "networking.firewall.enable"
check_opt "networking.firewall.allowedTCPPorts" "$FIREWALL_OK"
check_opt "networking.firewall.allowedUDPPorts" "$FIREWALL_OK"
check_opt "networking.firewall.checkReversePath"

# Nix — check specific sub-keys so cachix.nix and surface/config.nix don't false-positive
check_opt "nix.settings.substituters"
check_opt "nix.settings.trusted-public-keys"
check_opt "nix.settings.experimental-features"
check_opt "nix.settings.builders-use-substitutes"
check_opt "nix.gc.automatic"
check_opt "nix.gc.dates"
check_opt "nixpkgs.config.allowUnfree"

# Programs / services commonly over-declared
check_opt "programs.zsh.enable"
check_opt "programs.git.enable"
check_opt "services.openssh.enable"
check_opt "services.pipewire.enable"
check_opt "services.pipewire.pulse.enable"
check_opt "hardware.bluetooth.enable"
check_opt "hardware.enableRedistributableFirmware"
check_opt "fonts.packages"

echo
########################################
echo "── Duplicate package declarations"
########################################
# Skip files under pkgs/ — those are derivation definitions, not consumption

declare -A pkg_seen  # pkg -> "file1|file2|..."

while IFS= read -r nixfile; do
  # Skip derivation-definition files and other-user home configs
  # (home/family/ is a separate user account — packages there aren't duplicates of profiles/)
  echo "$nixfile" | grep -qE "^\./pkgs/|^\./home/family/" && continue
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    echo "$pkg" | grep -qE "^($PKG_SKIP)$" && continue
    [ ${#pkg} -le 2 ] && continue
    current="${pkg_seen[$pkg]:-}"
    if [[ "$current" != *"$nixfile"* ]]; then
      pkg_seen[$pkg]="${current:+$current|}$nixfile"
    fi
  done < <(
    # Skip entire makeBinPath [ ... ] blocks (multi-line) — those are per-script PATH deps.
    # Also skip ${pkgs.X}/bin/... interpolations and derivation input lists.
    awk '/makeBinPath/{mb=1} mb && /\]/{mb=0; next} mb{next} 1' "$nixfile" \
      | grep -v '\${pkgs\.\|buildInputs\|nativeBuildInputs\|propagatedBuildInputs' \
      | grep -oP '(?<=pkgs\.)(?>[a-zA-Z][a-zA-Z0-9_-]+)(?!\.)' 2>/dev/null \
      | grep -vE "^($PKG_SKIP)$" || true
  )
done < <(find . -name "*.nix" -not -path "./.git/*" -not -name "flake.lock")

pkg_dupes=0
for pkg in "${!pkg_seen[@]}"; do
  files="${pkg_seen[$pkg]}"
  count=$(echo "$files" | tr '|' '\n' | grep -c "\.nix" || true)
  if [ "$count" -ge 3 ]; then
    fail "\"$pkg\" declared in $count files — consolidate:"
    echo "$files" | tr '|' '\n' | while read -r f; do [ -n "$f" ] && echo "       $f"; done
    primary=$(echo "$files" | tr '|' '\n' | head -1)
    fix_note "Pick one canonical file for pkgs.$pkg (probably the most general), remove from the others"
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

declare -A imp_count

while IFS= read -r line; do
  imp=$(echo "$line" | grep -oP '\.\.?/[\w./]+\.nix' | head -1)
  [ -z "$imp" ] && continue
  imp=$(echo "$imp" | sed 's|^\./||')
  imp_count[$imp]=$((${imp_count[$imp]:-0} + 1))
done < <(grep -rh "^\s*\.\." --include="*.nix" . 2>/dev/null || true)

imp_issues=0
for imp in "${!imp_count[@]}"; do
  count="${imp_count[$imp]}"
  is_profile=$(echo "$imp" | grep -c "profiles/" || true)
  if [ "$is_profile" -gt 0 ]; then
    [ "$count" -gt 10 ] && warn "profile \"$imp\" imported $count times — unexpectedly high"
  else
    if [ "$count" -ge 4 ]; then
      fail "\"$imp\" imported $count times — should this be a profile?"
      fix_note "Move $imp into profiles/ and import it from there once per host"
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
# Two-pass: collect dead paths, then group by depth-2 ancestor prefix
# (e.g. all themes/Teams/*/file.nix → one git rm -r ./themes/Teams)

declare -a dead_files=()

while IFS= read -r nixfile; do
  base=$(basename "$nixfile")
  relpath=$(echo "$nixfile" | sed 's|^\./||')

  [[ "$base" == "flake.nix" ]] && continue
  [[ "$base" == "home.nix" ]] && continue
  [[ "$base" == "hardware-configuration.nix" ]] && continue
  [[ "$base" == "default.nix" ]] && continue
  # themes/ is a palette library — files are used on-demand, not via nix imports
  [[ "$relpath" == themes/* ]] && continue

  refs=$(grep -rl "$base" --include="*.nix" . 2>/dev/null \
    | grep -v "^\./$relpath$" \
    | grep -v "flake\.lock" \
    | wc -l || true)

  [ "$refs" -eq 0 ] && dead_files+=("$relpath")
done < <(find . -name "*.nix" -not -path "./.git/*" -not -name "flake.lock")

if [ "${#dead_files[@]}" -eq 0 ]; then
  pass "no dead .nix files"
else
  # Group by depth-2 prefix (first two path components)
  declare -A prefix_bucket  # prefix -> pipe-separated list of files

  for relpath in "${dead_files[@]}"; do
    IFS='/' read -ra parts <<< "$relpath"
    if [ "${#parts[@]}" -ge 3 ]; then
      prefix="${parts[0]}/${parts[1]}"
    else
      prefix="${parts[0]}"
    fi
    prefix_bucket[$prefix]+="${relpath}|"
  done

  # Determine which prefixes get bulk-deleted (3+ dead files under same ancestor)
  declare -A bulk_prefix=()
  for prefix in "${!prefix_bucket[@]}"; do
    count=$(echo "${prefix_bucket[$prefix]}" | tr '|' '\n' | grep -c "\.nix" || true)
    if [ "$count" -ge 3 ]; then
      fail "$count dead files under $prefix/ — entire subtree unused"
      fix_rm "-r ./$prefix"
      bulk_prefix[$prefix]=1
    fi
  done

  # Emit individual entries for files not covered by a bulk prefix
  for relpath in "${dead_files[@]}"; do
    IFS='/' read -ra parts <<< "$relpath"
    if [ "${#parts[@]}" -ge 3 ]; then
      prefix="${parts[0]}/${parts[1]}"
    else
      prefix="${parts[0]}"
    fi
    [[ -n "${bulk_prefix[$prefix]:-}" ]] && continue

    fail "\"$relpath\" not imported anywhere — dead file"
    fix_rm "./$relpath"
  done
fi

echo
########################################
echo "── Host files setting profile-level options"
########################################

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
      fix_note "Move \"$opt\" block to profiles/base.nix (or a relevant shared profile), remove from $host_file"
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
  echo "$stale_list" | while read -r f; do
    [ -n "$f" ] && echo "       $f"
    [ -n "$f" ] && fix_run "git rm $f"
  done
else
  pass "no stale backup files"
fi

echo
########################################
echo "── Environment variable style"
########################################

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
  fix_note "Pick one: sessionVariables (home-manager, user-login scope) or variables (system-wide). Convert the minority."
else
  pass "consistent environment variable style"
fi

echo
########################################
echo "── Hardcoded usernames in shared modules/profiles"
########################################

declare -A username_files_seen
hardcoded=0
while IFS= read -r match; do
  file=$(echo "$match" | cut -d: -f1)
  lineno=$(echo "$match" | cut -d: -f2)
  echo "$file" | grep -qE "^./hosts/" && continue
  echo "$file" | grep -qE "$GENERATED" && continue
  [[ -n "${username_files_seen[$file]:-}" ]] || {
    fail "hardcoded username in \"$(echo "$file" | sed 's|^\./||')\" — use a variable"
    fix_note "Replace literal \"prepko\" with a NixOS option (e.g. config.myConfig.user or a module argument)"
    fix_grep '"prepko"\|/home/prepko' "$(echo "$file" | sed 's|^\./||')"
    username_files_seen[$file]=1
    ((hardcoded++))
  }
done < <(grep -rn '"prepko"\|/home/prepko' --include="*.nix" . 2>/dev/null \
  | grep -v "flake\.lock" \
  | grep -v "^#" \
  | grep -v 'default\s*=\s*"prepko"\|mkOption\|description\s*=' \
  || true)
[ "$hardcoded" -eq 0 ] && pass "no hardcoded usernames in shared modules"

echo
########################################
echo "── Secrets hygiene"
########################################
# Look for actual credential leakage, not file extensions:
#   - literal password/token/apiKey values (not nix interpolations)
#   - absolute paths to secret-extension files not routed through sops
# Skip: lines already using config.sops.secrets, sopsFile declarations,
#        xdg.configFile keys (those are just config file names, not paths),
#        and comment lines.

secret_issues=0
declare -A secret_files_seen=()

while IFS= read -r match; do
  file=$(echo "$match" | cut -d: -f1)
  echo "$file" | grep -qE "$GENERATED" && continue
  relfile=$(echo "$file" | sed 's|^\./||')
  [[ -n "${secret_files_seen[$relfile]:-}" ]] || {
    warn "possible plaintext secret in \"$relfile\""
    fix_note "Replace literal value with: config.sops.secrets.\"<name>\".path (NixOS) or config.home.file via sops-nix HM module"
    fix_grep 'password\|token\|apiKey\|api_key\|secret' "$relfile"
    secret_files_seen[$relfile]=1
    ((secret_issues++))
  }
done < <(
  # Literal password/token/apiKey assignments — value is a plain string, not a ${...} interpolation
  grep -rn \
    -e 'password[[:space:]]*=[[:space:]]*"[^{$\\][^"]*"' \
    -e '[aA][pP][iI][_-]\?[kK][eE][yY][[:space:]]*=[[:space:]]*"[^{$\\]' \
    -e '[tT]oken[[:space:]]*=[[:space:]]*"[a-zA-Z0-9_-]\{16,\}' \
    --include="*.nix" . 2>/dev/null \
  | grep -v 'flake\.lock' \
  | grep -v 'config\.sops\.secrets' \
  | grep -v 'sopsFile[[:space:]]*=' \
  | grep -v 'xdg\.configFile\.' \
  | grep -v '[[:space:]]*#' \
  || true
)

# Separate check: absolute paths to secret-extension files not going through sops
while IFS= read -r match; do
  file=$(echo "$match" | cut -d: -f1)
  echo "$file" | grep -qE "$GENERATED" && continue
  relfile=$(echo "$file" | sed 's|^\./||')
  [[ -n "${secret_files_seen[$relfile]:-}" ]] || {
    warn "hardcoded secret file path in \"$relfile\" — use sops"
    fix_note "Replace with: config.sops.secrets.\"<name>\".path"
    fix_grep '\.key\|\.pem\|\.ovpn\|\.env' "$relfile"
    secret_files_seen[$relfile]=1
    ((secret_issues++))
  }
done < <(
  grep -rn '"\/[^"]*\.\(key\|pem\|ovpn\|env\|secret\)[^"]*"' \
    --include="*.nix" . 2>/dev/null \
  | grep -v 'flake\.lock' \
  | grep -v 'config\.sops\.secrets' \
  | grep -v 'sopsFile[[:space:]]*=' \
  | grep -v '[[:space:]]*#' \
  || true
)

[ "$secret_issues" -eq 0 ] && pass "no obvious hardcoded secrets"

echo
########################################
# Scoring
########################################

TOTAL=$((PASS + WARN + FAIL))
[ "$TOTAL" -eq 0 ] && TOTAL=1

SCORE=$(( (PASS * 100 + WARN * 60) / TOTAL ))

echo "────────────────────────────────"
echo "Results: $TOTAL checks"
echo "  ✔ passed: $PASS"
echo "  ~ warned: $WARN"
echo "  ✗ failed: $FAIL"
echo

if   [ "$SCORE" -ge 93 ]; then GRADE="A"; MSG="excellent — very clean config"
elif [ "$SCORE" -ge 83 ]; then GRADE="B"; MSG="good, minor issues to address"
elif [ "$SCORE" -ge 72 ]; then GRADE="C"; MSG="moderate duplication, worth a cleanup pass"
elif [ "$SCORE" -ge 60 ]; then GRADE="D"; MSG="significant redundancy — refactor recommended"
else                            GRADE="F"; MSG="major duplication — needs real work"
fi

echo "Grade: $GRADE ($SCORE/100) — $MSG"

########################################
# Fix summary
########################################

if [ "${#AUTO_FIX[@]}" -gt 0 ] || [ "${#MANUAL_FIX[@]}" -gt 0 ]; then
  echo
  echo "────────────────────────────────"
  echo "Fix plan"
  echo

  if [ "${#AUTO_FIX[@]}" -gt 0 ]; then
    printf "${cC}Safe to run (dead files / stale backups — reversible via git):${cX}\n"
    printf "${cD}  Run with: ./tools/grade-redundancy.sh --fix${cX}\n"
    echo
    for cmd in "${AUTO_FIX[@]}"; do
      echo "  $cmd"
    done
    echo
  fi

  if [ "${#MANUAL_FIX[@]}" -gt 0 ]; then
    printf "${cY}Needs your judgment (consolidation, parameterization):${cX}\n"
    echo
    printf '%s\n' "${MANUAL_FIX[@]}" | sort -u | while read -r note; do
      echo "  • $note"
    done
    echo
  fi
fi

########################################
# --fix mode: apply the git rm queue
########################################

if $FIX_MODE; then
  if [ "${#AUTO_FIX[@]}" -eq 0 ]; then
    echo "Nothing safe to auto-fix."
  else
    echo "────────────────────────────────"
    echo "Applying safe fixes..."
    echo
    for cmd in "${AUTO_FIX[@]}"; do
      echo "  + $cmd"
      eval "$cmd" 2>&1 | sed 's/^/    /' || true
    done
    echo
    echo "Done. Review with: git status"
    echo "Undo all:          git checkout HEAD -- ."
  fi
fi
