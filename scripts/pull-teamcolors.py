#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["requests"]
# ///
"""
Pull team colors from thesportsdb.com + jimniels/teamcolors and write teamcolors.json.
Colors from both sources are merged into a flat `colors` array per team.
Usage:  uv run scripts/pull-teamcolors.py [--out PATH]
"""

import argparse
import json
import re
import sys
import time
import requests

LEAGUES = [
    ("NBA",        "NBA"),
    ("NFL",        "NFL"),
    ("NHL",        "NHL"),
    ("MLB",        "MLB"),
    ("MLS",        "American Major League Soccer"),
    ("EPL",        "English Premier League"),
    ("LaLiga",     "Spanish La Liga"),
    ("Bundesliga", "German Bundesliga"),
    ("SerieA",     "Italian Serie A"),
    ("Ligue1",     "French Ligue 1"),
    ("PKMN",       "Pokemon"),
]

# jimniels only covers these leagues
LEAGUE_TO_JIMNIELS = {
    "NBA": "nba", "NFL": "nfl", "NHL": "nhl",
    "MLB": "mlb", "MLS": "mls", "EPL": "epl",
}

THESPORTSDB_API = "https://www.thesportsdb.com/api/v1/json/3/search_all_teams.php"
JIMNIELS_URL    = "https://raw.githubusercontent.com/jimniels/teamcolors/main/src/teams.json"


def _norm(name: str) -> str:
    return re.sub(r'[^a-z0-9 ]', '', name.lower()).strip()


def fetch_jimniels() -> dict[tuple, list[str]]:
    """Fetch jimniels/teamcolors. Returns {(league, normalized_name): ['#hex', ...]}"""
    resp = requests.get(JIMNIELS_URL, timeout=10)
    resp.raise_for_status()
    out = {}
    for t in resp.json():
        league = t.get("league", "").lower()
        name   = _norm(t.get("name", ""))
        colors = ["#" + c.lstrip("#") for c in t.get("colors", {}).get("hex", []) if c]
        if colors:
            out[(league, name)] = colors
    return out


def merge_colors(*color_lists) -> list[str]:
    """Combine color lists, dedup by exact normalized hex, preserve order."""
    seen = set()
    out  = []
    for lst in color_lists:
        for c in (lst or []):
            if not c:
                continue
            key = c.lower().lstrip('#')
            if key not in seen:
                seen.add(key)
                out.append(c if c.startswith('#') else '#' + c)
    return out


def fetch_league(abbr: str, league: str, jimniels: dict) -> list[dict]:
    resp  = requests.get(THESPORTSDB_API, params={"l": league}, timeout=10)
    resp.raise_for_status()
    teams = resp.json().get("teams") or []
    jimniels_league = LEAGUE_TO_JIMNIELS.get(abbr)
    out   = []
    for t in teams:
        c1 = (t.get("strColour1") or "").strip()
        if not c1:
            continue
        c2 = (t.get("strColour2") or "").strip() or None
        c3 = (t.get("strColour3") or "").strip() or None
        sdb_colors = [c for c in [c1, c2, c3] if c]

        jim_colors = []
        if jimniels_league:
            jim_colors = jimniels.get((jimniels_league, _norm(t["strTeam"])), [])

        out.append({
            "name":      t["strTeam"],
            "league":    abbr,
            "primary":   c1,
            "secondary": c2,
            "tertiary":  c3,
            "aliases":   [t["strTeam"].lower()],
            "colors":    merge_colors(sdb_colors, jim_colors),
        })
    return out

def fetch_pokemon():
    # The raw JS file containing the object constant
    URL = "https://raw.githubusercontent.com/davemlz/ee-pokepalettes/main/pokepalettes/pokepalettes.js"
    try:
        resp = requests.get(URL, timeout=10)
        resp.raise_for_status()

        # Use regex to find "pokemon_name": ["#hex1", "#hex2"...]
        # This bypasses the JS syntax and pulls just the data
        pattern = r'"([^"]+)":\s*\[([^\]]+)\]'
        matches = re.findall(pattern, resp.text)

        out = []
        for name, hex_str in matches:
            # Clean up the hex string list
            hex_list = [h.strip().strip('"').strip("'") for h in hex_str.split(',')]

            if not hex_list:
                continue

            out.append({
                "name":      name.capitalize(),
                "league":    "PKMN",
                "primary":   hex_list[0],
                "secondary": hex_list[1] if len(hex_list) > 1 else None,
                "tertiary":  hex_list[2] if len(hex_list) > 2 else None,
                "aliases":   [name.lower()],
                "colors":    merge_colors(hex_list),
            })
        return out
    except Exception as e:
        print(f"  PKMN fetch failed: {e}", file=sys.stderr)
        return []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="teamcolors.json")
    args = parser.parse_args()

    print("Fetching jimniels/teamcolors...")
    try:
        jimniels = fetch_jimniels()
        print(f"  {len(jimniels)} teams loaded")
    except Exception as e:
        print(f"  WARNING: jimniels fetch failed ({e}) — using thesportsdb only", file=sys.stderr)
        jimniels = {}

    all_teams = []
    for abbr, league in LEAGUES:
        try:
            # Check if we are fetching Pokemon or Sports
            if abbr == "PKMN":
                teams = fetch_pokemon()
                matched = 0 # Pokemon data is natively enriched
            else:
                teams = fetch_league(abbr, league, jimniels)
                matched = sum(1 for t in teams if len(t["colors"]) > len([c for c in [t["primary"], t["secondary"], t["tertiary"]] if c]))

            print(f"  {abbr:12s} {len(teams):3d} teams  ({matched} enriched by jimniels)")
            all_teams.extend(teams)
        except Exception as e:
            print(f"  {abbr:12s} FAILED: {e}", file=sys.stderr)
        time.sleep(0.3)

    all_teams.sort(key=lambda t: (t["league"], t["name"]))

    with open(args.out, "w") as f:
        json.dump(all_teams, f, indent=2)

    print(f"\n{len(all_teams)} teams → {args.out}")


if __name__ == "__main__":
    main()
