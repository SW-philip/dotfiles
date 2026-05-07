#!/usr/bin/env python3
"""Fuzzel-based Waybar theme picker. Right-click on custom/choose_mode."""

import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata
from pathlib import Path

NIXOS_ROOT   = Path.home() / "nixos"
TEAMS_DIR    = NIXOS_ROOT / "themes" / "Teams"
TEAMCOLORS   = NIXOS_ROOT / "home" / "waybar" / "scripts" / "teamcolors.json"
LOG          = Path.home() / ".local" / "state" / "theme-picker.log"


def log(msg: str) -> None:
    with LOG.open("a") as f:
        f.write(msg + "\n")


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


def plain_line(name: str, league: str) -> str:
    tag = f"  [{league}]" if league else ""
    return f"{name}{tag}"


def activate(slug: str, theme_dir: Path) -> None:
    palette_sh     = theme_dir / f"palette-{slug}.sh"
    waybar_palette = Path.home() / ".config" / "waybar" / "palette.sh"
    state_dir      = Path.home() / ".local" / "state"
    state_dir.mkdir(parents=True, exist_ok=True)

    log(f"activate: slug={slug!r} palette={palette_sh} exists={palette_sh.exists()}")

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
    LOG.parent.mkdir(parents=True, exist_ok=True)
    log("=== theme-picker started ===")

    if not TEAMS_DIR.exists():
        log(f"TEAMS_DIR missing: {TEAMS_DIR}")
        sys.exit(f"themes/Teams not found: {TEAMS_DIR}")

    lookup = build_lookup()
    entries: list[tuple[str, str]] = []   # (display_line, slug)

    for theme_dir in sorted(TEAMS_DIR.iterdir()):
        if not theme_dir.is_dir():
            continue
        slug = theme_dir.name
        info = lookup.get(slug)

        if info:
            name, league = info["name"], info["league"]
        else:
            name   = slug.replace("-", " ").title()
            league = "Custom"

        entries.append((plain_line(name, league), slug))

    known  = sorted([(d, s) for d, s in entries if s in lookup],  key=lambda x: x[0])
    custom = sorted([(d, s) for d, s in entries if s not in lookup], key=lambda x: x[0])
    entries = known + custom

    line_to_slug = {d: s for d, s in entries}
    lines = "\n".join(d for d, _ in entries)
    log(f"built {len(entries)} entries")

    fuzzel_cfg = "[main]\nfont=monospace:size=13\nlines=20\nwidth=35\ndpi-aware=auto\nlayer=overlay\n"
    with tempfile.NamedTemporaryFile("w", suffix=".ini", delete=False) as f:
        f.write(fuzzel_cfg)
        cfg_path = f.name

    result = subprocess.run(
        ["fuzzel", "--dmenu", "--prompt", " theme: ", "--config", cfg_path],
        input=lines, capture_output=True, text=True,
    )

    Path(cfg_path).unlink(missing_ok=True)
    log(f"fuzzel returncode={result.returncode!r} stdout={result.stdout!r}")

    if result.returncode != 0 or not result.stdout.strip():
        sys.exit(0)

    selection = result.stdout.strip()
    slug = line_to_slug.get(selection)
    log(f"selection={selection!r} → slug={slug!r}")

    if not slug:
        log(f"ERROR: no slug for selection")
        sys.exit(f"picker: unknown selection {selection!r}")

    activate(slug, TEAMS_DIR / slug)


if __name__ == "__main__":
    main()
