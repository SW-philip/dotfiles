#!/usr/bin/env python3
"""
AFL Jellyfin Batch Renamer
Parses filenames like: westernBulldogs_gwsGiants_14March26.mp4
Renames to:           AFL - S2026E05 - Western Bulldogs vs GWS Giants.mp4
  (inside AFL (2026)/Season 2026/ folder structure)

Usage:
  python3 afl_rename.py /srv/Videos/AFL          # dry run (safe, shows what would happen)
  python3 afl_rename.py /srv/Videos/AFL --commit  # actually rename/move files
"""

import os
import re
import sys
import json
import time
import argparse
import urllib.request
from pathlib import Path
from datetime import datetime, date

# ---------------------------------------------------------------------------
# Team name mapping: camelCase tokens -> display name
# Handles multi-word clubs by trying longest match first
# ---------------------------------------------------------------------------
TEAM_TOKENS = {
    "adelaidecrows":     "Adelaide Crows",
    "adelaide":          "Adelaide Crows",
    "brisbanelions":     "Brisbane Lions",
    "brisbane":          "Brisbane Lions",
    "carltonblues":      "Carlton Blues",
    "carlton":           "Carlton Blues",
    "collingwoodmagpies":"Collingwood Magpies",
    "collingwood":       "Collingwood Magpies",
    "essendondons":      "Essendon Bombers",
    "essendonbombers":   "Essendon Bombers",
    "essendon":          "Essendon Bombers",
    "fremantledockers":  "Fremantle Dockers",
    "fremantle":         "Fremantle Dockers",
    "geelongcats":       "Geelong Cats",
    "geelong":           "Geelong Cats",
    "goldcoastsuns":     "Gold Coast Suns",
    "goldcoast":         "Gold Coast Suns",
    "gwsgiants":         "GWS Giants",
    "greaterwestern":    "GWS Giants",
    "gws":               "GWS Giants",
    "hawthornhawks":     "Hawthorn Hawks",
    "hawthorn":          "Hawthorn Hawks",
    "melbournedemons":   "Melbourne Demons",
    "melbourne":         "Melbourne Demons",
    "northmelbournekangaroos": "North Melbourne Kangaroos",
    "northmelbourne":    "North Melbourne Kangaroos",
    "portadelaidepowerfc":"Port Adelaide Power",
    "portadelaide":      "Port Adelaide Power",
    "richmond":          "Richmond Tigers",
    "richmondtigers":    "Richmond Tigers",
    "stkildafc":         "St Kilda Saints",
    "stkilda":           "St Kilda Saints",
    "sydneyswans":       "Sydney Swans",
    "sydney":            "Sydney Swans",
    "westcoasteagles":   "West Coast Eagles",
    "westcoast":         "West Coast Eagles",
    "westernbulldogs":   "Western Bulldogs",
    "bulldogs":          "Western Bulldogs",
}

MONTH_MAP = {
    "jan":1,"feb":2,"mar":3,"apr":4,"may":5,"jun":6,
    "jul":7,"aug":8,"sep":9,"oct":10,"nov":11,"dec":12,
    "january":1,"february":2,"march":3,"april":4,"june":6,
    "july":7,"august":8,"september":9,"october":10,"november":11,"december":12,
}

# ---------------------------------------------------------------------------
# Squiggle API – free, no key needed, covers AFL since 1897
# https://api.squiggle.com.au
# ---------------------------------------------------------------------------
_round_cache: dict[int, list[dict]] = {}

def fetch_rounds(year: int) -> list[dict]:
    if year in _round_cache:
        return _round_cache[year]
    url = f"https://api.squiggle.com.au/?q=games;year={year}"
    req = urllib.request.Request(url, headers={"User-Agent": "afl-jellyfin-renamer/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            data = json.loads(r.read())
        games = data.get("games", [])
        _round_cache[year] = games
        time.sleep(0.3)   # be polite to the free API
        return games
    except Exception as e:
        print(f"  [WARN] Could not fetch AFL schedule for {year}: {e}")
        return []

def round_for_date(match_date: date) -> int | None:
    """Return the AFL round number for a given match date."""
    games = fetch_rounds(match_date.year)
    date_str = match_date.strftime("%Y-%m-%d")
    for g in games:
        if g.get("date", "").startswith(date_str):
            return int(g["round"])
    # fallback: find closest game date
    closest = None
    closest_delta = 999
    for g in games:
        try:
            gd = datetime.strptime(g["date"][:10], "%Y-%m-%d").date()
            delta = abs((gd - match_date).days)
            if delta < closest_delta:
                closest_delta = delta
                closest = int(g["round"])
        except Exception:
            continue
    if closest is not None and closest_delta <= 3:
        return closest
    return None

# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def split_camel(token: str) -> str:
    """gwsGiants -> gws Giants (split on uppercase boundary)"""
    return re.sub(r'([a-z])([A-Z])', r'\1 \2', token)

def parse_team(raw: str) -> str:
    """Try to map a raw camelCase token to a display team name."""
    key = raw.lower().replace(" ", "")
    # longest-match scan
    for length in range(len(key), 0, -1):
        for start in range(len(key) - length + 1):
            sub = key[start:start+length]
            if sub in TEAM_TOKENS:
                return TEAM_TOKENS[sub]
    # fallback: title-case the camel-split version
    return split_camel(raw).title()

def parse_date(raw: str) -> date | None:
    """
    Handles formats like:
      14March26  14Mar26  14March2026  14-03-26  2026-03-14  20260314
    """
    raw = raw.strip()

    # DDMonthYY or DDMonthYYYY
    m = re.fullmatch(r'(\d{1,2})([A-Za-z]+)(\d{2,4})', raw)
    if m:
        day, mon, yr = int(m.group(1)), m.group(2).lower()[:3], int(m.group(3))
        month = MONTH_MAP.get(mon) or MONTH_MAP.get(m.group(2).lower())
        if month:
            year = 2000 + yr if yr < 100 else yr
            try:
                return date(year, month, day)
            except ValueError:
                pass

    # YYYYMMDD
    m = re.fullmatch(r'(\d{4})(\d{2})(\d{2})', raw)
    if m:
        try:
            return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            pass

    # DD-MM-YY or DD-MM-YYYY or YYYY-MM-DD
    for fmt in ("%d-%m-%y", "%d-%m-%Y", "%Y-%m-%d", "%d/%m/%Y"):
        try:
            return datetime.strptime(raw, fmt).date()
        except ValueError:
            pass

    return None

def parse_filename(name: str) -> dict | None:
    """
    Expects:  teamA_teamB_datepart.ext
    Returns dict with keys: team1, team2, match_date, ext
    """
    stem, ext = os.path.splitext(name)
    parts = stem.split("_")
    if len(parts) < 3:
        return None

    # date is always the last token
    date_raw = parts[-1]
    match_date = parse_date(date_raw)
    if not match_date:
        return None

    team1 = parse_team(parts[0])
    team2 = parse_team("_".join(parts[1:-1]))  # middle parts = team2

    return {
        "team1": team1,
        "team2": team2,
        "match_date": match_date,
        "ext": ext,
    }

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def build_new_path(base: Path, info: dict, round_num: int | None) -> Path:
    year = info["match_date"].year
    ep = round_num if round_num else info["match_date"].timetuple().tm_yday // 7 + 1
    season_dir = base / f"AFL ({year})" / f"Season {year}"
    filename = f"AFL - S{year}E{ep:02d} - {info['team1']} vs {info['team2']}{info['ext']}"
    return season_dir / filename

def process(directory: str, commit: bool):
    root = Path(directory)
    if not root.exists():
        print(f"Directory not found: {directory}")
        sys.exit(1)

    # collect all video files (non-recursive at top level, adjust glob if nested)
    exts = {".mp4", ".mkv", ".avi", ".m4v", ".mov", ".ts"}
    files = [f for f in root.rglob("*") if f.suffix.lower() in exts]

    if not files:
        print("No video files found.")
        return

    print(f"Found {len(files)} file(s). {'DRY RUN – no changes made.' if not commit else 'COMMITTING changes.'}\n")

    ok = skipped = 0
    for f in sorted(files):
        info = parse_filename(f.name)
        if not info:
            print(f"  SKIP  {f.name}  (could not parse)")
            skipped += 1
            continue

        round_num = round_for_date(info["match_date"])
        new_path = build_new_path(root, info, round_num)

        round_label = f"R{round_num}" if round_num else "R??"
        print(f"  {round_label}  {f.name}")
        print(f"       → {new_path.relative_to(root)}")

        if commit:
            new_path.parent.mkdir(parents=True, exist_ok=True)
            f.rename(new_path)

        ok += 1

    print(f"\nDone. {ok} renamed, {skipped} skipped.")
    if not commit:
        print("\nRun with --commit to apply changes.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Rename AFL recordings for Jellyfin")
    parser.add_argument("directory", help="Path to your AFL video folder")
    parser.add_argument("--commit", action="store_true",
                        help="Actually rename files (default is dry run)")
    args = parser.parse_args()
    process(args.directory, args.commit)
