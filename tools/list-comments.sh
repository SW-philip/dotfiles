#!/usr/bin/env bash
# list-comments.sh — collect non-obvious comments from nix files for review
#
# Excludes:
#   - shebangs (#!)
#   - pure divider lines (######, -----, etc.)
#   - blank comment lines
#   - section-header labels: a comment line that immediately follows a #####
#     divider (with optional blank line between), and is ≤ 6 words with no
#     code-like characters
#
# Usage: ./tools/list-comments.sh [root-dir]
# Output: commentlist.txt in the root dir

set -uo pipefail

ROOT="${1:-$(pwd)}"
OUT="$ROOT/commentlist.txt"

# Chars passed to awk via ENVIRON (avoids bash single-quote / hex-range issues).
export _BOX_HDASH="─"          # U+2500 — box-drawing divider detection
export _NXMLDELIM="''"         # Nix '' multiline-string delimiter

cd "$ROOT"

total=0

{
  printf '# comment review list\n'
  printf '# generated: %s\n' "$(date)"
  printf '# root: %s\n\n' "$ROOT"

  while IFS= read -r nixfile; do
    relfile="${nixfile#./}"

    # Per-file: awk does one-pass context-aware extraction.
    # State: after_divider=1 means the previous significant line was a #### divider.
    # A "section header" is a short comment immediately after a divider.
    entries=$(awk '
      function ltrim(s) { sub(/^[[:space:]]+/, "", s); return s }
      function rtrim(s) { sub(/[[:space:]]+$/, "", s); return s }
      function trim(s)  { return rtrim(ltrim(s)) }

      function is_divider(s,    t, bd) {
        t = ltrim(s)
        # Lines that are only #, -, =, ~, *, space
        if (t ~ /^[#\-=~\* ]+$/ && length(t) > 0) return 1
        # Box-drawing style: # ── Word ──────── (U+2500 ─ and relatives)
        # Strip leading # and spaces, then check if the line starts with a
        # box-drawing char passed via ENVIRON (avoids awk hex-range limitations).
        sub(/^#+[[:space:]]*/, "", t)
        bd = ENVIRON["_BOX_HDASH"]
        if (bd != "" && index(t, bd) == 1) return 1
        return 0
      }

      function word_count(s,    n, arr) {
        n = split(s, arr, /[[:space:]]+/)
        return n
      }

      function has_code(s) {
        return (s ~ /[=\{\}\[\];]/ || \
                s ~ /pkgs\.|config\.|lib\.|options\.|services\.|programs\.|home\./ || \
                s ~ /---|\.\.\.|TODO|FIXME|HACK|FIX:|NOTE:|TEMP|XXX/)
      }

      BEGIN {
        after_divider = 0; in_ml = 0
        ml_delim = ENVIRON["_NXMLDELIM"]
        sq = sprintf("%c", 39)   # single-quote char — avoids bash quoting issues
      }

      {
        raw = $0
        stripped = ltrim(raw)

        # Track Nix '' multiline-string state.
        # Only update on non-comment lines — '' inside a Nix comment is text,
        # not a string delimiter, so it must not affect in/out state.
        # Lines that START inside a '' string are content (CSS etc.), not comments.
        starts_in_ml = in_ml
        if (stripped !~ /^#/ && ml_delim != "") {
          tmp = raw; n = 0
          while ((idx = index(tmp, ml_delim)) > 0) {
            nch = substr(tmp, idx + 2, 1)
            if (nch != "$" && nch != sq) n++
            tmp = substr(tmp, idx + 2)
          }
          if (n % 2) in_ml = 1 - in_ml
        }
        if (starts_in_ml) { if (stripped != "") after_divider = 0; next }

        # Track dividers — set flag, then skip
        if (is_divider(stripped)) {
          after_divider = 1
          next
        }

        # Only process comment lines from here
        if (stripped !~ /^#/) {
          # Non-comment, non-divider line resets the divider flag
          if (stripped != "") after_divider = 0
          next
        }

        # Strip leading # chars and one optional space to get comment text
        text = stripped
        sub(/^#+[[:space:]]?/, "", text)
        text = trim(text)

        # Skip shebangs
        if (stripped ~ /^#!/) { after_divider = 0; next }

        # Skip blank comments
        if (text == "") { next }

        # Skip pure dividers (the text itself is only dashes/hashes/etc.)
        if (text ~ /^[-=~#\* \/]+$/) { next }

        # If we are right after a divider, this is likely a section header.
        # Exclude it if it looks like a title: ≤ 6 words and no code chars.
        if (after_divider) {
          after_divider = 0
          if (!has_code(text) && word_count(text) <= 6) next
        }

        # Exclude very short labels even outside divider context:
        # 1-2 words with no code chars are almost certainly section sub-labels.
        if (!has_code(text) && word_count(text) <= 2) next

        # CSS ID selectors inside Nix multiline strings look like Nix comments
        # (# is stripped → "entry {", "entry:selected {", "lock:hover { ... }").
        # Pattern: single-word CSS selector with optional pseudo-class, then {
        if (text ~ /^[a-z][a-zA-Z0-9_-]*(:[a-zA-Z-]+)?[[:space:]]*\{/) next

        print NR ": " text
      }
    ' "$nixfile")

    if [ -n "$entries" ]; then
      printf '── %s\n' "$relfile"
      while IFS= read -r entry; do
        printf '  %s\n' "$entry"
        ((total++))
      done <<< "$entries"
      printf '\n'
    fi

  done < <(find . -name "*.nix" -not -path "./.git/*" -not -path "./themes/*" -not -name "flake.lock" | sort)

  printf '# total: %d comments\n' "$total"
} > "$OUT"

printf 'Found %d comments → %s\n' "$total" "$OUT"
