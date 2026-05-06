REPO=$(git -C "$(dirname "$0")" rev-parse
cd "$REPO" || exit 1

sep() { printf "\n=== %s ===\n\n" "$*"; }

HOST_CONFIGS=$(find ./hosts -name "config.nix" | sort)
HOME_PROFILES=$(find ./profiles/home -name "*.nix" | sort)
NIX_FILES=$(find . -name "*.nix" \
    ! -path "./themes/' | while read -r line; do

        case "$line" in
            "{"*|"}"*|"];"*|"]"*|"["*|"..."*|"inputs."*) continue ;;
            "imports"*|"./hardware.nix"*|"./boot.nix"*) continue ;;
        esac
        [ ${#line} -lt 10 ] && continue
        printf '%s\t%s\n' "$line" "$short"
    done
done > "$tmpdir/all_lines"


sort "$tmpdir/all_lines" | awk -F'\t' '
{
    line = $1; file = $2
    if (!(line in files) || index(files[line], file) == 0) {
        files[line] = files[line] " " file
        count[line]++
    }
}
END {
    for (line in count)
        if (count[line] >= 2)
            print count[line] "\t" line "\t" files[line]
}' | sort -t$'\t' -k1,1nr -k2,2 | awk -F'\t' '{
    printf "  [%s hosts] %s\n", $1, $2
    printf "    in:%s\n", $3
}'

rm -rf "$tmpdir"



sep "IDENTICAL LINES IN BOTH desktop.nix AND surface.nix HOME PROFILES"
echo "These should move to profiles/home/base.nix:"
echo ""

comm -12 \
    <(grep -v '^\s*$' profiles/home/desktop.nix | grep -v '^\s*#' | sed 's/^[[:space:]]*//' | \
      grep -v '^{$\|^}$\|^];\|imports\|./base.nix\|^../' | awk 'length>4' | sort) \
    <(grep -v '^\s*$' profiles/home/surface.nix | grep -v '^\s*#' | sed 's/^[[:space:]]*//' | \
      grep -v '^{$\|^}$\|^];\|imports\|./base.nix\|^../' | awk 'length>4' | sort) \
| sed 's/^/  /'



sep "PACKAGES IN MULTIPLE HOME PROFILES (non-base)"
echo "These appear in 2+ of: desktop.nix, surface.nix, family.nix — consider base.nix:"
echo ""

non_base_profiles=$(find ./profiles/home -name "*.nix" ! -name "base.nix" | sort)

tmpdir=$(mktemp -d)
for f in $non_base_profiles; do
    short="${f#./profiles/home/}"

    grep -oP '(?<=^\s{4})[a-zA-Z][a-zA-Z0-9_-]+$' "$f" >> "$tmpdir/$short"
done 2>/dev/null


all_pkgs=$(cat "$tmpdir"/* 2>/dev/null | sort | uniq -d)
for pkg in $all_pkgs; do
    files=$(grep -rl "^$pkg$" "$tmpdir"/ 2>/dev/null | xargs -I{} basename {} | tr '\n' '  ')
    echo "  $pkg  →  $files"
done | sort

rm -rf "$tmpdir"



sep "LARGE FILES (>150 lines)"
echo ""

echo "$NIX_FILES" | while IFS= read -r f; do
    lines=$(wc -l < "$f")
    [ "$lines" -gt 150 ] && printf "  %4d  %s\n" "$lines" "${f#./}"
done | sort -nr



sep "MODULES IMPORTED EXACTLY ONCE (consider inlining)"
echo ""

echo "$NIX_FILES" | while IFS= read -r mod; do
    relpath="${mod#./}"
    basename_mod=$(basename "$mod")
    count=$(grep -rl "$basename_mod"
        ! -path "./themes/*" ! -path "./.git/*" 2>/dev/null | \
        grep -v "^\./$relpath$" | wc -l)
    if [ "$count" -eq 1 ]; then
        importer=$(grep -rl "$basename_mod"
            ! -path "./themes/*" ! -path "./.git/*" 2>/dev/null | \
            grep -v "^\./$relpath$" | head -1)
        printf "  %-50s ← %s\n" "$relpath" "${importer#./}"
    fi
done | sort