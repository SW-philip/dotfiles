#!/usr/bin/env bash
# nix-repo-audit.sh — pre-public sweep for a NixOS flake repo
# usage: ./nix-repo-audit.sh [path-to-repo]   (defaults to cwd)
# philosophy: surface, don't filter. read every section.

set -uo pipefail

REPO="${1:-$(pwd)}"
cd "$REPO" || { echo "can't cd to $REPO"; exit 1; }

# colors only if stdout is a tty
if [ -t 1 ]; then
  R=$'\e[31m'; Y=$'\e[33m'; G=$'\e[32m'; B=$'\e[34m'; D=$'\e[2m'; N=$'\e[0m'
else
  R=''; Y=''; G=''; B=''; D=''; N=''
fi

section() { printf "\n${B}== %s ==${N}\n" "$1"; }
hit()     { printf "${R}  ! %s${N}\n" "$1"; }
warn()    { printf "${Y}  ~ %s${N}\n" "$1"; }
ok()      { printf "${G}  ✓ %s${N}\n" "$1"; }
note()    { printf "${D}    %s${N}\n" "$1"; }

# ---------------------------------------------------------------------------
# 0. sanity — are we in a git repo with a flake?
# ---------------------------------------------------------------------------
section "0. sanity check"
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  hit "not a git repo"; exit 1
fi
[ -f flake.nix ] && ok "flake.nix present" || warn "no flake.nix at root"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
note "branch: $BRANCH"
note "remote: $(git remote -v | head -1 || echo none)"

# files git is actually tracking — most checks should respect .gitignore
TRACKED=$(git ls-files)

# ---------------------------------------------------------------------------
# 1. high-confidence secret patterns (working tree, tracked files only)
# ---------------------------------------------------------------------------
section "1. secret patterns in tracked files"

# patterns that are almost never false positives
declare -a HARD_PATTERNS=(
  'AKIA[0-9A-Z]{16}'                              # AWS access key
  'AIza[0-9A-Za-z_-]{35}'                         # Google API key
  'ghp_[0-9A-Za-z]{36}'                           # GitHub PAT (classic)
  'github_pat_[0-9A-Za-z_]{82}'                   # GitHub PAT (fine-grained)
  'sk-[a-zA-Z0-9]{20,}'                           # OpenAI / Anthropic style
  'xox[baprs]-[0-9a-zA-Z-]{10,}'                  # Slack tokens
  '-----BEGIN (RSA |OPENSSH |EC |DSA |PGP )?PRIVATE KEY-----'
  'AGE-SECRET-KEY-1[0-9A-Z]{58}'                  # age secret key
)

FOUND_HARD=0
for pat in "${HARD_PATTERNS[@]}"; do
  matches=$(echo "$TRACKED" | xargs -d '\n' grep -EnH "$pat" 2>/dev/null || true)
  if [ -n "$matches" ]; then
    hit "pattern: $pat"
    echo "$matches" | sed 's/^/      /'
    FOUND_HARD=1
  fi
done
[ $FOUND_HARD -eq 0 ] && ok "no hard-pattern matches"

# softer patterns — review manually
section "2. soft patterns (review each)"
declare -a SOFT=(
  'password\s*='
  'passwd\s*='
  'secret\s*='
  'api[_-]?key'
  'token\s*='
  'bearer '
)
for pat in "${SOFT[@]}"; do
  matches=$(echo "$TRACKED" | xargs -d '\n' grep -EinH "$pat" 2>/dev/null \
    | grep -v '\.sops\.yaml' \
    | grep -v 'secrets/.*\.yaml' \
    | grep -v 'sopsFile' \
    | grep -v '# noqa' || true)
  if [ -n "$matches" ]; then
    warn "$pat"
    echo "$matches" | sed 's/^/      /'
  fi
done

# ---------------------------------------------------------------------------
# 3. sops-nix specific — encrypted files are fine, unencrypted ones are not
# ---------------------------------------------------------------------------
section "3. sops / age artifacts"

# any .yaml in secrets/ that doesn't look encrypted
for f in $(echo "$TRACKED" | grep -E '(secrets/.*\.ya?ml$|\.sops\.ya?ml$)' || true); do
  if grep -q 'sops:' "$f" 2>/dev/null; then
    ok "encrypted: $f"
  else
    hit "looks like a secrets file but no 'sops:' block: $f"
  fi
done

# any age/ssh keys committed
for f in $(echo "$TRACKED" | grep -E '(\.age$|/age\.txt$|id_rsa$|id_ed25519$|\.key$)' || true); do
  hit "private key file tracked: $f"
done

# ---------------------------------------------------------------------------
# 4. identifying info
# ---------------------------------------------------------------------------
section "4. identifying info"

# /home/<username> paths — your username will leak if hardcoded
USERNAME=$(whoami)
home_hits=$(echo "$TRACKED" | xargs -d '\n' grep -nH "/home/$USERNAME" 2>/dev/null || true)
if [ -n "$home_hits" ]; then
  warn "hardcoded /home/$USERNAME paths (consider \${config.home.homeDirectory})"
  echo "$home_hits" | sed 's/^/      /' | head -20
fi

# RFC1918 IPs — your LAN topology
lan_hits=$(echo "$TRACKED" \
  | xargs -d '\n' grep -EnH '(^|[^0-9])(10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)' 2>/dev/null \
  | grep -v '# audit-ok' || true)
if [ -n "$lan_hits" ]; then
  warn "private-range IPs (LAN topology leak)"
  echo "$lan_hits" | sed 's/^/      /' | head -20
fi

# MAC addresses
mac_hits=$(echo "$TRACKED" \
  | xargs -d '\n' grep -EnH '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' 2>/dev/null \
  | grep -vi 'example\|aa:bb\|00:00:00:00:00:00' || true)
if [ -n "$mac_hits" ]; then
  warn "MAC addresses (wake-on-lan etc.)"
  echo "$mac_hits" | sed 's/^/      /' | head -10
fi

# email addresses in source (separate from commit metadata)
email_hits=$(echo "$TRACKED" \
  | xargs -d '\n' grep -EnH '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' 2>/dev/null \
  | grep -v '# audit-ok' \
  | grep -v 'example\.com\|example\.org\|noreply' || true)
if [ -n "$email_hits" ]; then
  warn "email addresses in source"
  echo "$email_hits" | sed 's/^/      /' | head -10
fi

# disk UUIDs in hardware-configuration.nix — usually fine, but worth flagging
if [ -n "$(echo "$TRACKED" | grep hardware-configuration)" ]; then
  note "hardware-configuration.nix present (disk UUIDs leak — usually acceptable)"
fi

# ---------------------------------------------------------------------------
# 5. git history sweep
# ---------------------------------------------------------------------------
section "5. git history (this is the one that bites)"

# search all of history for the hard patterns
hist_hits=0
for pat in "${HARD_PATTERNS[@]}"; do
  matches=$(git log -p --all -S "$(echo "$pat" | sed 's/[].*+?()|\\^$[]/_/g; s/_\{2,\}/_/g; s/_/./g')" 2>/dev/null \
    | grep -E "$pat" | head -3 || true)
  # the -S above is best-effort; do a slower but correct grep-through-log too
done

# the correct (slow) way: scan every blob
note "scanning every blob in history for hard patterns..."
all_blobs=$(git rev-list --objects --all | awk '{print $1}' | sort -u | head -5000)
hist_found=0
while IFS= read -r blob; do
  for pat in "${HARD_PATTERNS[@]}"; do
    if git cat-file -p "$blob" 2>/dev/null | grep -Eq "$pat"; then
      hit "blob $blob contains: $pat"
      git log --all --oneline --find-object="$blob" 2>/dev/null | head -2 | sed 's/^/      /'
      hist_found=1
      break
    fi
  done
done <<< "$all_blobs"
[ $hist_found -eq 0 ] && ok "no hard patterns found in scanned blobs"

# ---------------------------------------------------------------------------
# 6. git config & author info
# ---------------------------------------------------------------------------
section "6. commit authorship"
authors=$(git log --format='%an <%ae>' --all | sort -u)
echo "$authors" | sed 's/^/    /'
note "if any author/email here surprises you, fix before pushing"

# ---------------------------------------------------------------------------
# 7. untracked / ignored sanity
# ---------------------------------------------------------------------------
section "7. .gitignore sanity"
declare -a SHOULD_IGNORE=(
  '*.key' '*.pem' 'id_rsa' 'id_ed25519'
  '.env' '.env.*'
  'result' 'result-*'
  '.direnv'
)
if [ -f .gitignore ]; then
  for pat in "${SHOULD_IGNORE[@]}"; do
    grep -qF "$pat" .gitignore && ok "ignores: $pat" || warn "consider ignoring: $pat"
  done
else
  warn "no .gitignore"
fi

# ---------------------------------------------------------------------------
# 8. flake.lock — public, but worth noting
# ---------------------------------------------------------------------------
section "8. flake.lock"
if [ -f flake.lock ]; then
  ok "flake.lock present (will be public — this is normal)"
  # check for any inputs pointing to private repos
  priv=$(grep -E '"url":\s*"(git\+ssh|ssh://)' flake.lock 2>/dev/null || true)
  if [ -n "$priv" ]; then
    hit "flake.lock references private (ssh) inputs:"
    echo "$priv" | sed 's/^/      /'
  fi
fi

# ---------------------------------------------------------------------------
# 9. README / LICENSE
# ---------------------------------------------------------------------------
section "9. public-repo etiquette"
[ -f README.md ] || warn "no README.md"
[ -f LICENSE ] || warn "no LICENSE (consider MIT or CC0 for dotfiles)"

printf "\n${B}== done ==${N}\n"
printf "${D}    red = fix before pushing. yellow = read and decide.${N}\n\n"
