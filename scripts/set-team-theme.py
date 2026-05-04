#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
set-team-theme — look up a sports team and activate its palette.

First use of a team:  writes palette files → prompts you to run nrs once.
Subsequent uses:      instant — calls set-theme directly.

Usage:
    python3 scripts/set-team-theme.py "Philadelphia 76ers"
    python3 scripts/set-team-theme.py flyers
    python3 scripts/set-team-theme.py --list nba
    python3 scripts/set-team-theme.py --data path/to/teamcolors-full.json
"""

import argparse
import json
import os
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

# ── Paths ─────────────────────────────────────────────────────────────────────

NIXOS_ROOT      = Path(__file__).parent.parent
TEAMS_DIR       = NIXOS_ROOT / "themes" / "Teams"
DEFAULT_DATA    = NIXOS_ROOT / "scripts" / "teamcolors-full.json"
MAKE_WALLPAPER  = NIXOS_ROOT / "scripts" / "make-lix-wallpaper.sh"

# ── Minimal HSL color math (no deps) ─────────────────────────────────────────

def _hex_to_hsl(h: str) -> tuple[float, float, float]:
    r, g, b = int(h[1:3], 16)/255, int(h[3:5], 16)/255, int(h[5:7], 16)/255
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2
    if mx == mn:
        return 0.0, 0.0, l
    d = mx - mn
    s = d / (2 - mx - mn) if l > 0.5 else d / (mx + mn)
    if mx == r:   hue = (g - b) / d + (6 if g < b else 0)
    elif mx == g: hue = (b - r) / d + 2
    else:         hue = (r - g) / d + 4
    return hue / 6, s, l

def _hsl_to_hex(h: float, s: float, l: float) -> str:
    if s == 0:
        v = round(l * 255)
        return f"#{v:02x}{v:02x}{v:02x}"
    def _hue(p, q, t):
        t %= 1
        if t < 1/6: return p + (q - p) * 6 * t
        if t < 1/2: return q
        if t < 2/3: return p + (q - p) * (2/3 - t) * 6
        return p
    q = l * (1 + s) if l < 0.5 else l + s - l * s
    p = 2 * l - q
    r, g, b = _hue(p, q, h + 1/3), _hue(p, q, h), _hue(p, q, h - 1/3)
    return f"#{round(r*255):02x}{round(g*255):02x}{round(b*255):02x}"

def _darken(hex_color: str, amount: float) -> str:
    h, s, l = _hex_to_hsl(hex_color)
    return _hsl_to_hex(h, s, max(0.0, l - amount))

def _at_lightness(hex_color: str, lightness: float) -> str:
    h, s, _ = _hex_to_hsl(hex_color)
    return _hsl_to_hex(h, s, lightness)

# ── Wallpaper color derivation ────────────────────────────────────────────────

def derive_wallpaper_colors(p: dict) -> dict:
    """Map palette keys → Lix cone wallpaper color variables."""
    return {
        "BG_DARK":        _darken(p["BASE"], 0.05),
        "BG_LIGHT":       p["LOVE"],
        "ICE_SHADOW":     _darken(p["BASE"], 0.05),
        "ICE_MID":        p["IRIS"],
        "ICE_HIGHLIGHT":  _at_lightness(p["IRIS"], 0.91),
        "CONE_SHADOW":    _darken(p["BASE"], 0.12),
        "CONE_MID":       p["PINE"],
        "CONE_HIGHLIGHT": _at_lightness(p["PINE"], 0.78),
        "STICKER":        p["GOLD"],
    }

def write_wallpaper_colors(path: Path, wc: dict, team_name: str):
    lines = [f"# {team_name} — ice cream cone wallpaper colors"]
    for key, val in wc.items():
        lines.append(f'{key}="{val}"')
    path.write_text("\n".join(lines) + "\n")

def build_wallpaper(slug: str) -> bool:
    """Run make-lix-wallpaper.sh for slug. Returns True on success."""
    if not MAKE_WALLPAPER.exists():
        return False
    result = subprocess.run(
        ["bash", str(MAKE_WALLPAPER), slug],
        capture_output=True, text=True, cwd=str(NIXOS_ROOT)
    )
    return result.returncode == 0

# ── Slug / name helpers ────────────────────────────────────────────────────────

def slugify(name: str) -> str:
    """'Philadelphia 76ers' → 'philadelphia-76ers'"""
    name = unicodedata.normalize("NFKD", name)
    name = name.encode("ascii", "ignore").decode()
    name = name.lower().strip()
    name = re.sub(r"[^a-z0-9]+", "-", name)
    return name.strip("-")


def fuzzy_match(query: str, teams: list[dict]) -> list[dict]:
    """Return teams whose name or aliases contain all query tokens."""
    tokens = query.lower().split()
    results = []
    for t in teams:
        haystack = t["name"].lower() + " " + " ".join(t.get("aliases", []))
        if all(tok in haystack for tok in tokens):
            results.append(t)
    return results

# ── File generation ───────────────────────────────────────────────────────────

def write_nix(path: Path, p: dict, team_name: str):
    path.write_text(f"""\
{{
  # ── Base ──────────────────────────────────────────────────────
  BASE           = "{p['BASE']}";
  SURFACE        = "{p['SURFACE']}";
  OVERLAY        = "{p['OVERLAY']}";
  HIGHLIGHT_LOW  = "{p['HIGHLIGHT_LOW']}";
  HIGHLIGHT_MED  = "{p['HIGHLIGHT_MED']}";
  HIGHLIGHT_HIGH = "{p['HIGHLIGHT_HIGH']}";

  # ── Text & accents ────────────────────────────────────────────
  MUTED  = "{p['MUTED']}";
  SUBTLE = "{p['SUBTLE']}";
  TEXT   = "{p['TEXT']}";
  LOVE   = "{p['LOVE']}";
  ROSE   = "{p['ROSE']}";
  GOLD   = "{p['GOLD']}";
  PINE   = "{p['PINE']}";
  FOAM   = "{p['FOAM']}";
  IRIS   = "{p['IRIS']}";

  # ── Extended — named system-state colors ──────────────────────
  CRITICAL   = "{p['CRITICAL']}";
  WARNING    = "{p['WARNING']}";
  CAUTION    = "{p['CAUTION']}";
  MUTED_ICON = "{p['MUTED_ICON']}";

  # ── Structural (computed from base) ───────────────────────────
  INACTIVE_BORDER = "{p['INACTIVE_BORDER']}";
  SHADOW          = "{p['SHADOW']}";

  # ── Waybar module background tiers ────────────────────────────
  WB_BASE    = "{p['WB_BASE']}";
  WB_SURFACE = "{p['WB_SURFACE']}";
  WB_OVERLAY = "{p['WB_OVERLAY']}";

  # ── Gradient depth anchors ────────────────────────────────────
  GRAD_SURFACE_HI = "{p['GRAD_SURFACE_HI']}";
  GRAD_SURFACE_LO = "{p['GRAD_SURFACE_LO']}";
  GRAD_OVERLAY_HI = "{p['GRAD_OVERLAY_HI']}";
  GRAD_OVERLAY_LO = "{p['GRAD_OVERLAY_LO']}";
  GRAD_BASE_HI    = "{p['GRAD_BASE_HI']}";
  GRAD_BASE_LO    = "{p['GRAD_BASE_LO']}";

  # ── Accent border tints (R,G,B format for rgba()) ────────────
  BORDER_ACCENT_RGB = "{p['BORDER_ACCENT_RGB']}";
  BORDER_IRIS_RGB   = "{p['BORDER_IRIS_RGB']}";

  # ── Derived tinted backgrounds ────────────────────────────────
  TINT_PINE_DARK   = "{p['TINT_PINE_DARK']}";
  TINT_PINE_MID    = "{p['TINT_PINE_MID']}";
  TINT_CRITICAL_BG = "{p['TINT_CRITICAL_BG']}";

  # ── State-tinted hover backgrounds ────────────────────────────
  HOVER_MUTED_BG  = "{p['HOVER_MUTED_BG']}";
  HOVER_TEAL_BG   = "{p['HOVER_TEAL_BG']}";
  HOVER_GREEN_BG  = "{p['HOVER_GREEN_BG']}";
  HOVER_GOLD_BG   = "{p['HOVER_GOLD_BG']}";
  HOVER_ORANGE_BG = "{p['HOVER_ORANGE_BG']}";

  # ── Bar typography ───────────────────────────────────────────
  FONT_SIZE_BAR = "{p.get('FONT_SIZE_BAR', '12px')}";
  ICON_SHADOW   = "{p.get('ICON_SHADOW', '0 1px 2px rgba(0,0,0,0.80)')}";

  # ── Box-shadow composition ───────────────────────────────────
  SHADOW_RGB     = "{p['SHADOW_RGB']}";
  SHADOW_A_OUTER = "{p.get('SHADOW_A_OUTER', '0.50')}";
  SHADOW_A_DROP  = "{p.get('SHADOW_A_DROP',  '0.55')}";
  SHADOW_A_HOVER = "{p.get('SHADOW_A_HOVER', '0.65')}";
  INSET_TOP_A    = "{p.get('INSET_TOP_A',    '0.08')}";
  INSET_BOT_A    = "{p.get('INSET_BOT_A',    '0.30')}";
  BORDER_TOP_A   = "{p.get('BORDER_TOP_A',   '0.07')}";

  # ── Battery (anchored to theme semantic colors) ───────────────
  BATTERY_FULL = "{p['BATTERY_FULL']}";
  BATTERY_HIGH = "{p['BATTERY_HIGH']}";
  BATTERY_MED  = "{p['BATTERY_MED']}";
  BATTERY_LOW  = "{p['BATTERY_LOW']}";
  BATTERY_CRIT = "{p['BATTERY_CRIT']}";

  # ── Named accent roles ────────────────────────────────────────
  BORDER_ACCENT    = "{p['BORDER_ACCENT']}";
  ACCENT_PRIMARY   = "{p['ACCENT_PRIMARY']}";
  TEXT_PRIMARY     = "{p['TEXT_PRIMARY']}";
  TEXT_SECONDARY   = "{p['TEXT_SECONDARY']}";
  ACCENT_SECONDARY = "{p['ACCENT_SECONDARY']}";
}}
""")


def write_sh(path: Path, p: dict, team_name: str):
    path.write_text(f"""\
#!/usr/bin/env bash
# {team_name} — generated palette for waybar scripts

# ── Base colors ───────────────────────────────────────────────
BASE="{p['BASE']}"
SURFACE="{p['SURFACE']}"
OVERLAY="{p['OVERLAY']}"
MUTED="{p['MUTED']}"
SUBTLE="{p['SUBTLE']}"
TEXT="{p['TEXT']}"

# ── Accent spectrum ───────────────────────────────────────────
LOVE="{p['LOVE']}"
ROSE="{p['ROSE']}"
GOLD="{p['GOLD']}"
PINE="{p['PINE']}"
FOAM="{p['FOAM']}"
IRIS="{p['IRIS']}"

# ── Highlight tiers ───────────────────────────────────────────
HIGHLIGHT_LOW="{p['HIGHLIGHT_LOW']}"
HIGHLIGHT_MED="{p['HIGHLIGHT_MED']}"
HIGHLIGHT_HIGH="{p['HIGHLIGHT_HIGH']}"

# ── Structural ───────────────────────────────────────────────
SHADOW="{p['SHADOW']}"
INACTIVE_BORDER="{p['INACTIVE_BORDER']}"

# ── Waybar bar tiers ──────────────────────────────────────────
WB_BASE="{p['WB_BASE']}"
WB_SURFACE="{p['WB_SURFACE']}"
WB_OVERLAY="{p['WB_OVERLAY']}"

# ── Text roles ────────────────────────────────────────────────
TEXT_PRIMARY="$TEXT"
TEXT_SECONDARY="$SUBTLE"
INK="$TEXT_PRIMARY"

# ── Accent roles ──────────────────────────────────────────────
ACCENT_PRIMARY="{p['ACCENT_PRIMARY']}"
ACCENT_SECONDARY="{p['ACCENT_SECONDARY']}"
BORDER_ACCENT="{p['BORDER_ACCENT']}"

# ── Battery semantic colors ───────────────────────────────────
BATTERY_CRIT="{p['BATTERY_CRIT']}"
BATTERY_LOW="{p['BATTERY_LOW']}"
BATTERY_MED="{p['BATTERY_MED']}"
BATTERY_HIGH="{p['BATTERY_HIGH']}"
BATTERY_FULL="{p['BATTERY_FULL']}"

# ── Status roles ──────────────────────────────────────────────
WARN="$GOLD"
ERROR="$LOVE"
SUCCESS="$FOAM"
INFO="$IRIS"

# ── Weather semantic colors ───────────────────────────────────
WX_SUN_LIGHT="$GOLD"
WX_SUN_MEDIUM="$ROSE"
WX_SUN_HEAVY="$LOVE"
WX_RAIN_LIGHT="$FOAM"
WX_RAIN_MEDIUM="$ACCENT_SECONDARY"
WX_RAIN_HEAVY="$PINE"
WX_CLOUD_LIGHT="$TEXT_SECONDARY"
WX_CLOUD_MEDIUM="$SUBTLE"
WX_CLOUD_HEAVY="$MUTED"
WX_SNOW_LIGHT="$TEXT_PRIMARY"
WX_SNOW_HEAVY="$FOAM"
WX_FOG_LIGHT="$SUBTLE"
WX_FOG_HEAVY="$MUTED"
WX_STORM_HEAVY="$LOVE"
""")
    path.chmod(0o755)

# ── Theme registration ────────────────────────────────────────────────────────

def register_theme(team: dict) -> tuple[str, bool]:
    """
    Write palette + wallpaper files under themes/Teams/<slug>/.
    Returns (slug, already_existed).
    """
    slug       = slugify(team["name"])
    theme_dir  = TEAMS_DIR / slug
    palette    = team["palette"]
    team_name  = team["name"]

    already = theme_dir.exists()
    theme_dir.mkdir(parents=True, exist_ok=True)

    write_nix(theme_dir / f"palette-{slug}.nix", palette, team_name)
    write_sh( theme_dir / f"palette-{slug}.sh",  palette, team_name)

    wc = derive_wallpaper_colors(palette)
    write_wallpaper_colors(theme_dir / "wallpaper-colors.sh", wc, team_name)
    build_wallpaper(slug)

    return slug, already


def activate_team_theme(slug: str, theme_dir: Path) -> None:
    """
    Directly activate a team theme without nrs.
    Swaps the waybar palette and wallpaper; leaves all other theme config intact.
    """
    import shutil
    import time

    palette_sh     = theme_dir / f"palette-{slug}.sh"
    waybar_palette = Path.home() / ".config/waybar/palette.sh"
    state_dir      = Path.home() / ".local/state"
    state_dir.mkdir(parents=True, exist_ok=True)

    waybar_palette.unlink(missing_ok=True)
    shutil.copy2(palette_sh, waybar_palette)
    (state_dir / "theme").write_text(slug)

    wallpapers = sorted(theme_dir.glob("wallpaper-*.png"))
    if wallpapers:
        (state_dir / "wallpaper").write_text(str(wallpapers[0]))
        subprocess.run(["systemctl", "--user", "restart", "swaybg"],
                       capture_output=True)

    # Hide bar so color swap isn't visible as a flash
    subprocess.run(["pkill", "-SIGUSR1", "waybar"], capture_output=True)
    time.sleep(0.3)
    # Reload waybar last — safe here since set-team-theme is not a waybar child
    subprocess.run(["pkill", "-f", "waybar-weather"], capture_output=True)
    subprocess.run(["pkill", "-SIGUSR2", "waybar"], capture_output=True)

# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Set system theme to a sports team's colors."
    )
    parser.add_argument("query", nargs="?", help="Team name or partial match")
    parser.add_argument("--list", metavar="LEAGUE",
                        help="List available teams (optionally filter by league)")
    parser.add_argument("--data", default=str(DEFAULT_DATA),
                        help="Path to teamcolors-full.json")
    parser.add_argument("--register-only", action="store_true",
                        help="Write palette files but don't activate (useful for batch prep)")
    args = parser.parse_args()

    data_path = Path(args.data)
    if not data_path.exists():
        sys.exit(f"Data file not found: {data_path}\n"
                 f"Run: python3 scripts/enrich-teamcolors.py first.")

    teams = json.loads(data_path.read_text())

    # ── --list ────────────────────────────────────────────────────────────────
    if args.list is not None:
        league_filter = args.list.upper()
        filtered = [t for t in teams
                    if not league_filter or t["league"].upper() == league_filter
                    or league_filter in t["league"].upper()]
        if not filtered:
            sys.exit(f"No teams found for league: {args.list}")
        col_w = max(len(t["name"]) for t in filtered) + 2
        for t in sorted(filtered, key=lambda x: (x["league"], x["name"])):
            slug = slugify(t["name"])
            registered = (TEAMS_DIR / slug).exists()
            mark = "✓" if registered else " "
            print(f"  {mark} [{t['league']:10s}]  {t['name']:{col_w}}  {slug}")
        return

    # ── team query required from here ─────────────────────────────────────────
    if not args.query:
        parser.print_help()
        sys.exit(1)

    matches = fuzzy_match(args.query, teams)

    if not matches:
        print(f"No team matched: {args.query!r}")
        # suggest closest token overlap
        scored = sorted(teams,
            key=lambda t: sum(tok in t["name"].lower()
                              for tok in args.query.lower().split()),
            reverse=True)
        print("Closest matches:")
        for t in scored[:5]:
            print(f"  [{t['league']}] {t['name']}")
        sys.exit(1)

    if len(matches) > 1:
        print(f"Ambiguous query {args.query!r} — matched {len(matches)} teams:")
        for t in matches:
            print(f"  [{t['league']}] {t['name']}")
        sys.exit(1)

    team = matches[0]
    slug, already_existed = register_theme(team)

    p = team["palette"]
    print(f"[{team['league']}] {team['name']}")
    print(f"  BASE {p['BASE']}  IRIS {p['IRIS']}  LOVE {p['LOVE']}  GOLD {p['GOLD']}")
    print(f"  slug: {slug}")

    if not already_existed:
        print(f"  → wrote themes/Teams/{slug}/")
    else:
        print(f"  → updated themes/Teams/{slug}/")

    if args.register_only:
        return

    print("  → activating...")
    activate_team_theme(slug, TEAMS_DIR / slug)
    print("  done.")


if __name__ == "__main__":
    main()
