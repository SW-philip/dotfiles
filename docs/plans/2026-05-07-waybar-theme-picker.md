# Waybar Theme Picker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a right-click fuzzel picker to the `custom/choose_mode` Waybar module that lists all 20 Teams themes with Pango color swatches and friendly names.

**Architecture:** New `home/waybar/scripts/theme-picker.py` handles the full picker loop (enumerate themes → fuzzel → activate). Two changes to `home/waybar/default.nix`: update `chooseModeExec` tooltip to handle team theme slugs, and add `on-right-click` to both `custom/choose_mode` module definitions. Left-click cycling of Rose-Pine variants is unchanged.

**Tech Stack:** Python 3 stdlib only, fuzzel `--dmenu --markup`, nix path interpolation for store-safe script referencing.

---

### Task 1: Create `home/waybar/scripts/theme-picker.py`

**Files:**
- Create: `home/waybar/scripts/theme-picker.py`

**Step 1: Write the script**

```python
#!/usr/bin/env python3
"""Fuzzel-based Waybar theme picker. Right-click on custom/choose_mode."""

import json
import re
import shutil
import subprocess
import sys
import time
import unicodedata
from pathlib import Path

NIXOS_ROOT   = Path.home() / "nixos"
TEAMS_DIR    = NIXOS_ROOT / "themes" / "Teams"
TEAMCOLORS   = NIXOS_ROOT / "home" / "waybar" / "scripts" / "teamcolors.json"


def slugify(name: str) -> str:
    name = unicodedata.normalize("NFKD", name)
    name = name.encode("ascii", "ignore").decode()
    name = name.lower().strip()
    name = re.sub(r"[^a-z0-9]+", "-", name)
    return name.strip("-")


def parse_sh(path: Path) -> dict:
    """Parse KEY="value" / export KEY="value" shell env files."""
    result = {}
    for line in path.read_text().splitlines():
        line = line.strip().removeprefix("export").strip()
        if "=" not in line or line.startswith("#"):
            continue
        key, _, val = line.partition("=")
        result[key.strip()] = val.strip().strip('"')
    return result


def build_lookup() -> dict:
    """slug → {name, league, c1, c2} from teamcolors.json."""
    if not TEAMCOLORS.exists():
        return {}
    teams = json.loads(TEAMCOLORS.read_text())
    out = {}
    for t in teams:
        slug = slugify(t["name"])
        c2 = t.get("tertiary") or t.get("secondary") or "#6e6a86"
        out[slug] = {
            "name":   t["name"],
            "league": t.get("league", ""),
            "c1":     t.get("primary", "#908caa"),
            "c2":     c2,
        }
    return out


def pango_line(name: str, league: str, c1: str, c2: str) -> str:
    swatches = (
        f'<span foreground="{c1}">██</span>'
        f'<span foreground="{c2}">██</span>'
    )
    tag = f"  [{league}]" if league else ""
    return f"{swatches}  {name}{tag}"


def activate(slug: str, theme_dir: Path) -> None:
    palette_sh     = theme_dir / f"palette-{slug}.sh"
    waybar_palette = Path.home() / ".config" / "waybar" / "palette.sh"
    state_dir      = Path.home() / ".local" / "state"
    state_dir.mkdir(parents=True, exist_ok=True)

    waybar_palette.unlink(missing_ok=True)
    shutil.copy2(palette_sh, waybar_palette)
    (state_dir / "theme").write_text(slug)

    wallpapers = sorted(theme_dir.glob("wallpaper-*.png"))
    if wallpapers:
        (state_dir / "wallpaper").write_text(str(wallpapers[0]))
        subprocess.run(["systemctl", "--user", "restart", "swaybg"],
                       capture_output=True)

    subprocess.run(["pkill", "-SIGUSR1", "waybar"], capture_output=True)
    time.sleep(0.3)
    subprocess.run(["pkill", "-f", "waybar-weather"], capture_output=True)
    subprocess.run(["pkill", "-SIGUSR2", "waybar"], capture_output=True)  # LAST


def main() -> None:
    if not TEAMS_DIR.exists():
        sys.exit(f"themes/Teams not found: {TEAMS_DIR}")

    lookup = build_lookup()
    entries: list[tuple[str, str]] = []   # (display_line, slug)

    for theme_dir in sorted(TEAMS_DIR.iterdir()):
        if not theme_dir.is_dir():
            continue
        slug = theme_dir.name
        info = lookup.get(slug)

        if info:
            name, league, c1, c2 = info["name"], info["league"], info["c1"], info["c2"]
        else:
            name   = slug.replace("-", " ").title()
            league = "Custom"
            palette_sh = theme_dir / f"palette-{slug}.sh"
            if palette_sh.exists():
                pal = parse_sh(palette_sh)
                c1  = pal.get("ACCENT_PRIMARY",   "#908caa")
                c2  = pal.get("ACCENT_SECONDARY",  "#6e6a86")
            else:
                c1, c2 = "#908caa", "#6e6a86"

        entries.append((pango_line(name, league, c1, c2), slug))

    known  = sorted([(d, s) for d, s in entries if s in lookup],  key=lambda x: x[0])
    custom = sorted([(d, s) for d, s in entries if s not in lookup], key=lambda x: x[0])
    entries = known + custom

    line_to_slug = {d: s for d, s in entries}
    lines = "\n".join(d for d, _ in entries)

    result = subprocess.run(
        ["fuzzel", "--dmenu", "--markup", "--prompt", " theme: "],
        input=lines, capture_output=True, text=True,
    )

    if result.returncode != 0 or not result.stdout.strip():
        sys.exit(0)

    slug = line_to_slug.get(result.stdout.strip())
    if not slug:
        sys.exit(f"picker: unknown selection {result.stdout.strip()!r}")

    activate(slug, TEAMS_DIR / slug)


if __name__ == "__main__":
    main()
```

**Step 2: Make it executable**

```bash
chmod +x home/waybar/scripts/theme-picker.py
```

**Step 3: Dry-run verify (print lines, don't launch fuzzel)**

```bash
python3 - <<'EOF'
import sys
sys.argv = ['x']
# Monkey-patch subprocess to print instead of launching fuzzel
import subprocess as _sp
_real = _sp.run
def _fake(cmd, **kw):
    if 'fuzzel' in cmd:
        print("=== FUZZEL INPUT ===")
        print(kw.get('input', ''))
        class R:
            returncode = 1
            stdout = ''
        return R()
    return _real(cmd, **kw)
_sp.run = _fake

import importlib.util, pathlib
spec = importlib.util.spec_from_file_location("tp", pathlib.Path("home/waybar/scripts/theme-picker.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.main()
EOF
```

Expected: prints ~20 Pango-formatted lines, one per team/custom theme. Verify a few have recognizable colors (e.g. `#004C54` for Eagles, `#E81828` for Phillies).

**Step 4: Commit**

```bash
git add home/waybar/scripts/theme-picker.py
git commit -m "feat(waybar): add fuzzel theme picker script"
```

---

### Task 2: Update `chooseModeExec` in `home/waybar/default.nix`

**Files:**
- Modify: `home/waybar/default.nix:8-28`

**Context:** Current script only handles Rose-Pine variants. When `~/.local/state/theme` holds a team slug like `philadelphia-eagles`, the tooltip should show that slug in IRIS color instead of the broken cycle.

**Step 1: Replace `chooseModeExec` (lines 8–28)**

Replace the entire `chooseModeExec` let binding with:

```nix
chooseModeExec = pkgs.writeShellScript "choose-mode" ''
  export PATH="${pkgs.lib.makeBinPath [ pkgs.jq pkgs.coreutils ]}:$PATH"
  THEME=$(cat "$HOME/.local/state/theme" 2>/dev/null || echo "main")

  case "$THEME" in
    main|moon|dawn|light|lilac-juniper|dark)
      case "$THEME" in
        moon)          L=moon ;;
        dawn|light)    L=dawn ;;
        lilac-juniper) L="lilac·juniper" ;;
        *)             L=main ;;
      esac
      _s() {
        if [ "$1" = "$L" ]; then
          printf '<span foreground="${p.IRIS}"><b>%s</b></span>' "$1"
        else
          printf '<span foreground="${p.MUTED}">%s</span>' "$1"
        fi
      }
      TIP="$(_s main)  →  $(_s moon)  →  $(_s dawn)  →  $(_s "lilac·juniper")"
      ;;
    *)
      TIP="<span foreground=\"${p.IRIS}\">$THEME</span>"
      ;;
  esac

  jq -cn --arg text "󰔎" --arg tip "$TIP" '{text: $text, tooltip: $tip}'
'';
```

**Step 2: Verify nix syntax parses cleanly**

```bash
nix-instantiate --parse home/waybar/default.nix > /dev/null && echo OK
```

Expected: `OK` with no errors.

---

### Task 3: Add `on-right-click` to both `custom/choose_mode` blocks

**Files:**
- Modify: `home/waybar/default.nix:104-107` (desktop leftBottomBar)
- Modify: `home/waybar/default.nix:171-174` (surface surfaceBottomBar)

**Context:** There are two `"custom/choose_mode"` attribute sets — one under `leftBottomBar` (desktop, ~line 104) and one under `surfaceBottomBar` (surface, ~line 171). Both need the same `on-right-click` added.

**Step 1: Add `on-right-click` to the desktop block**

Find this block (around line 102):
```nix
"custom/choose_mode" = {
  exec = "${chooseModeExec}";
  on-click = "toggle-theme";
  return-type = "json";
  interval = "once";
};
```

Replace with:
```nix
"custom/choose_mode" = {
  exec = "${chooseModeExec}";
  on-click = "toggle-theme";
  on-right-click = "python3 ${./scripts/theme-picker.py}";
  return-type = "json";
  interval = "once";
};
```

**Step 2: Apply the same change to the surface block** (~line 169)

Same find-and-replace — the surface `custom/choose_mode` block also lacks `on-right-click`.

**Step 3: Verify nix syntax**

```bash
nix-instantiate --parse home/waybar/default.nix > /dev/null && echo OK
```

Expected: `OK`.

**Step 4: Commit nix changes**

```bash
git add home/waybar/default.nix
git commit -m "feat(waybar): wire theme picker to custom/choose_mode right-click"
```

---

### Task 4: Rebuild and verify end-to-end

**Step 1: Run nrs**

```bash
nrs
```

Expected: clean build, no errors.

**Step 2: Right-click the `󰔎` module**

Fuzzel opens with a list of ~20 themes. Verify:
- Each line has two colored block glyphs followed by a name and league tag
- Philly teams show their brand colors
- Custom themes (espresso, bay-breeze, etc.) appear at the bottom under `[Custom]`

**Step 3: Select a team theme**

Pick e.g. `Philadelphia Eagles [NFL]`. Verify:
- Wallpaper changes
- Waybar reloads (brief hide/show)
- Tooltip on `󰔎` now shows `philadelphia-eagles` in a muted color
- Right-click again → fuzzel opens again (waybar restarted cleanly)

**Step 4: Verify left-click still works**

Left-click `󰔎` → cycles through `main → moon → dawn → lilac·juniper`. Tooltip updates correctly.

**Step 5: Commit any fixups**

```bash
git add -p
git commit -m "fix(waybar): theme picker post-nrs fixups"
```
