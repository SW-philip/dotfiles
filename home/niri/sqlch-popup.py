#!/usr/bin/env python3
"""sqlch-popup — GTK4 layer-shell radio player popup."""

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Gtk4LayerShell', '1.0')
gi.require_version('GdkPixbuf', '2.0')
gi.require_version('Pango', '1.0')
from gi.repository import Gtk, GLib, GdkPixbuf, Gtk4LayerShell, Pango

import html
import json
import os
import random
import re
import socket
import subprocess
import hashlib
import threading
import time
import urllib.request
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
XDG_RUNTIME  = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
XDG_CACHE    = Path(os.environ.get("XDG_CACHE_HOME",  Path.home() / ".cache"))
XDG_DATA     = Path(os.environ.get("XDG_DATA_HOME",   Path.home() / ".local" / "share"))
CONTROL_SOCK  = XDG_RUNTIME / "sqlch" / "control.sock"
MPV_SOCK      = XDG_RUNTIME / "sqlch" / "mpv.sock"
CACHE_DIR     = XDG_CACHE / "sqlch"
COVERS_DIR    = CACHE_DIR / "covers"
LOGOS_DIR     = CACHE_DIR / "logos"
ENRICHED_JSON = CACHE_DIR / "enriched.json"
LIBRARY_JSON  = XDG_DATA  / "sqlch" / "library.json"
FREQ_CACHE_JSON = XDG_DATA / "sqlch" / "freq_cache.json"

# Stations with real, known Philadelphia frequencies — always get these exact values.
# Keys are the actual library station IDs (as produced by _normalize_id).
_KNOWN_FREQUENCIES: dict[str, str] = {
    "wxpn-885-philadelphia-pa": "88.5 FM",
    "wxpn-hd2-xponential":      "88.1 FM",
    "ynot-radio-philly":        "100.3 FM",
    # Generic fallbacks for manually-added variants
    "wxpn":        "88.5 FM",
    "xponential":  "88.1 FM",
    "ynot":        "100.3 FM",
    "whyy":        "90.9 FM",
    "wrti":        "90.1 FM",
    # Pool stations — added by call letters get their correct frequency
    "wxtu":  "92.5 FM",
    "wmmr":  "93.3 FM",
    "wip":   "94.1 FM",
    "wip-sportsradio-philadelphia": "94.1 FM",
    "wgmp":  "95.7 FM",
    "wpen":  "97.5 FM",
    "wogl":  "98.1 FM",
    "wusl":  "98.9 FM",
    "wbeb":  "101.1 FM",
    "wioq":  "102.1 FM",
    "wioq-q102": "102.1 FM",
    "wmgk":  "102.9 FM",
    "wsni":  "104.5 FM",
    "wdas":  "105.3 FM",
    "wkdn":  "106.9 FM",
    "wrnb":  "107.9 FM",
    "wurd":  "900 AM",
    "kyw":   "1060 AM",
    "wpht":  "1210 AM",
    "wbcb":  "1490 AM",
    "wnwr":  "1540 AM",
}

# Pool of real Philadelphia-area frequencies available for arbitrary new stations
_PHILLY_FREQ_POOL = [
    "92.5 FM",   # WXTU
    "93.3 FM",   # WMMR
    "94.1 FM",   # WIP
    "95.7 FM",   # WGMP
    "97.5 FM",   # WPEN
    "98.1 FM",   # WOGL
    "98.9 FM",   # WUSL
    "101.1 FM",  # WBEB
    "102.1 FM",  # WIOQ
    "102.9 FM",  # WMGK
    "104.5 FM",  # WSNI
    "105.3 FM",  # WDAS
    "106.9 FM",  # WKDN
    "107.9 FM",  # WRNB
    "900 AM",    # WURD
    "1060 AM",   # KYW
    "1210 AM",   # WPHT
    "1490 AM",   # WBCB
    "1540 AM",   # WNWR
]

POPUP_WIDTH = 360
ART_SIZE    = 84
POLL_MS     = 1500

# ── sqlch Python env (extracted at startup so no hardcoded store paths) ────────
def _find_sqlch_python() -> tuple[str, str] | None:
    """Return (python_bin, PYTHONPATH) by parsing the sqlch nix package entrypoint."""
    try:
        import shutil
        sqlch_bin = shutil.which("sqlch")
        if not sqlch_bin:
            return None
        # Follow symlinks to the actual nix store binary
        real = Path(os.path.realpath(sqlch_bin))
        # The python entrypoint is .sqlch-wrapped in the same bin dir
        py_entry = real.parent / ".sqlch-wrapped"
        if not py_entry.exists():
            return None
        text = py_entry.read_text()
        # First line: #!/path/to/python3.13
        py_bin = text.splitlines()[0].lstrip("#!").strip()
        # Extract site-packages list from the addsitedir call
        sites = re.findall(r"'(/nix/store/[^']+/site-packages)'", text)
        if not py_bin or not sites:
            return None
        return py_bin, ":".join(sites)
    except Exception:
        return None

_SQLCH_PY_ENV: tuple[str, str] | None = _find_sqlch_python()


def _download_cover(url: str) -> Path | None:
    """Download a cover URL to the covers cache using art_<hash>.jpg naming. Returns path or None."""
    try:
        COVERS_DIR.mkdir(parents=True, exist_ok=True)
        dest = COVERS_DIR / f"art_{hashlib.md5(url.encode()).hexdigest()}.jpg"
        if dest.exists():
            return dest
        tmp = dest.with_suffix(".tmp")
        req = urllib.request.Request(url, headers={"User-Agent": "sqlch-popup/1.0"})
        with urllib.request.urlopen(req, timeout=8) as resp, open(tmp, "wb") as f:
            f.write(resp.read())
        tmp.rename(dest)
        return dest
    except Exception:
        return None


def _logo_path(station_id: str) -> Path:
    """Return the cached logo path for a station (may not exist yet)."""
    safe = re.sub(r"[^\w-]", "_", station_id)
    return LOGOS_DIR / f"{safe}.img"


def _fetch_logo_url(station_name: str, station_url: str | None = None) -> str | None:
    """Query RadioBrowser for a station favicon URL. Returns URL string or None."""
    try:
        import urllib.parse
        # Try by URL first (exact match), then fall back to name search
        queries = []
        if station_url:
            queries.append(
                f"https://de1.api.radio-browser.info/json/stations/byurl"
                f"?url={urllib.parse.quote(station_url, safe='')}&limit=1&hidebroken=true"
            )
        queries.append(
            f"https://de1.api.radio-browser.info/json/stations/byname"
            f"/{urllib.parse.quote(station_name)}"
            f"?limit=5&hidebroken=true"
        )
        for query_url in queries:
            req = urllib.request.Request(
                query_url,
                headers={"User-Agent": "sqlch-popup/1.0", "Accept": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=6) as resp:
                results = json.loads(resp.read().decode())
            if results:
                favicon = results[0].get("favicon", "").strip()
                if favicon and favicon.startswith("http"):
                    return favicon
    except Exception:
        pass
    return None


def _download_logo(station_id: str, station_name: str, station_url: str | None = None) -> Path | None:
    """Fetch station logo from RadioBrowser and cache it. Returns path or None."""
    dest = _logo_path(station_id)
    if dest.exists():
        return dest
    favicon_url = _fetch_logo_url(station_name, station_url)
    if not favicon_url:
        return None
    try:
        LOGOS_DIR.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_suffix(".tmp")
        req = urllib.request.Request(favicon_url, headers={"User-Agent": "sqlch-popup/1.0"})
        with urllib.request.urlopen(req, timeout=8) as resp, open(tmp, "wb") as f:
            f.write(resp.read())
        tmp.rename(dest)
        return dest
    except Exception:
        return None


_LIVE_RE = re.compile(
    r'(?:[\s\-]+|\()'
    r'(live|bootleg|demo|acoustic|session|rehearsal|rare|outtake|alternate|unreleased|b-side|soundboard)'
    r'\b',
    re.IGNORECASE,
)

def _strip_live_qualifier(track: str) -> tuple[str, str | None]:
    """Return (base_track, qualifier) for live/bootleg/demo tracks, else (track, None).

    Detects qualifiers in parens, brackets, or after a separator:
      'Creep (Live at Glastonbury)' → ('Creep', 'live')
      'Black Star [Bootleg]'        → ('Black Star', 'bootleg')
      'High and Dry - Acoustic'     → ('High and Dry', 'acoustic')
    Does NOT match qualifiers at the very start of a title (avoids the band Live,
    album names like 'Live Forever', etc.).
    """
    m = _LIVE_RE.search(track)
    if not m:
        return track, None
    base = track[:m.start()].strip(' -([')
    return (base or track), m.group(1).lower()


def _resolve_cover_entry(entry: dict) -> tuple[Path | None, str | None]:
    """Resolve an enriched-cache entry to (local_path_or_None, cover_url_or_None)."""
    url = entry.get("cover") or None
    if not url:
        return None, None
    p = COVERS_DIR / f"art_{hashlib.md5(url.encode()).hexdigest()}.jpg"
    if p.exists():
        return p, url
    p = COVERS_DIR / f"{hashlib.md5((url + chr(10)).encode()).hexdigest()}.jpg"
    if p.exists():
        return p, url
    return None, url   # URL known but not yet cached


def run_enrich(artist: str, track: str) -> dict | None:
    """Run enrich_track via the sqlch Python env. Returns result dict or None."""
    if not _SQLCH_PY_ENV:
        return None
    py_bin, pythonpath = _SQLCH_PY_ENV
    script = (
        "import sys, site, functools\n"
        "functools.reduce(lambda k,p: site.addsitedir(p,k), "
        f"{pythonpath!r}.split(':'), site._init_pathinfo())\n"
        "import json, sys\n"
        "from sqlch.core.enrich import enrich_track\n"
        f"r = enrich_track({artist!r}, {track!r})\n"
        "print(json.dumps(r))"
    )
    try:
        result = subprocess.run(
            [py_bin, "-c", script],
            capture_output=True, text=True, timeout=20
        )
        if result.returncode == 0:
            return json.loads(result.stdout.strip())
    except Exception:
        pass
    return None

# ── CSS ───────────────────────────────────────────────────────────────────────
def _load_palette() -> dict:
    """Parse ~/.config/waybar/palette.sh into a color dict. Falls back to Rosé Pine Moon."""
    p = {
        "BASE": "#232136", "SURFACE": "#2a273f", "OVERLAY": "#393552",
        "HIGHLIGHT_LOW": "#2a283e", "HIGHLIGHT_MED": "#44415a", "HIGHLIGHT_HIGH": "#56526e",
        "MUTED": "#6e6a86", "SUBTLE": "#908caa", "TEXT": "#e0def4",
        "LOVE": "#eb6f92", "PINE": "#3e8fb0", "FOAM": "#9ccfd8",
        "ROSE": "#ea9a97", "IRIS": "#c4a7e7", "GOLD": "#f6c177",
        "SHADOW": "#0f0e17", "SHADOW_RGB": "15,14,23",
    }
    path = Path.home() / ".config" / "waybar" / "palette.sh"
    if path.exists():
        try:
            for line in path.read_text().splitlines():
                m = re.match(r'^export\s+(\w+)="([^"]*)"', line)
                if m:
                    p[m.group(1)] = m.group(2)
        except Exception:
            pass
    return p


def _build_css(p: dict) -> bytes:
    B  = p.get("BASE",           "#232136")
    S  = p.get("SURFACE",        "#2a273f")
    O  = p.get("OVERLAY",        "#393552")
    HL = p.get("HIGHLIGHT_LOW",  "#2a283e")
    HM = p.get("HIGHLIGHT_MED",  "#44415a")
    HH = p.get("HIGHLIGHT_HIGH", "#56526e")
    MU = p.get("MUTED",          "#6e6a86")
    SU = p.get("SUBTLE",         "#908caa")
    TX = p.get("TEXT",           "#e0def4")
    LV = p.get("LOVE",           "#eb6f92")
    PI = p.get("PINE",           "#3e8fb0")
    FM = p.get("FOAM",           "#9ccfd8")
    RS = p.get("ROSE",           "#ea9a97")
    IR = p.get("IRIS",           "#c4a7e7")
    GD = p.get("GOLD",           "#f6c177")
    SH = p.get("SHADOW",         "#0f0e17")
    SR = p.get("SHADOW_RGB",     "15,14,23")
    return f"""
* {{ -gtk-icon-style: symbolic; }}
window {{ background: transparent; }}

/* ── Outer popup (paper card) ── */
.popup {{
  background: {B};
  border: 2px solid {SH};
  border-radius: 12px;
  margin: 4px;
  box-shadow: 4px 5px 0 0 {SH};
}}

/* ── Now-playing card ── */
.now-playing {{
  background: {S};
  border-radius: 10px 10px 4px 4px;
  padding: 10px 12px;
  border-bottom: 2px solid {SH};
}}

/* ── Art panel ── */
.art-panel {{
  background: {B};
  border-radius: 8px;
  border: 2px solid {SH};
  padding: 2px;
  min-width: 86px;
  min-height: 86px;
  box-shadow: 2px 3px 0 0 {SH};
}}

/* ── Info panel (right of art) ── */
.info-panel {{
  background: {O};
  border-radius: 8px;
  padding: 4px 8px;
  border: 2px solid {SH};
  box-shadow: 2px 3px 0 0 {SH};
}}

/* ── Text display bubbles ── */
.display-bar {{
  background: {B};
  border-radius: 6px;
  margin: 3px 0 0;
  padding: 2px 6px;
  border: 1px solid {SH};
}}

/* ── Indicator strip ── */
.indicator-panel {{
  background: {B};
  border-radius: 6px;
  margin: 4px 0 2px;
  padding: 4px 6px;
  border: 1px solid {SH};
}}

/* ── Text ── */
.station-name {{
  font-family: "JetBrains Mono", "Courier New", monospace;
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.08em;
  color: {TX};
}}
.track-info {{
  font-family: "JetBrains Mono", "Courier New", monospace;
  font-size: 10px;
  letter-spacing: 0.05em;
  color: {PI};
}}
.meta-album {{
  font-family: "JetBrains Mono", "Courier New", monospace;
  font-size: 10px;
  font-weight: 600;
  color: {SU};
  letter-spacing: 0.04em;
}}
.meta-sub {{
  font-family: "JetBrains Mono", "Courier New", monospace;
  font-size: 9px;
  color: {MU};
  letter-spacing: 0.03em;
}}

/* ── Orbit animations ── */
@keyframes orbit-center-pulse {{
  0%, 100% {{ opacity: 0.5; }}
  50%       {{ opacity: 1.0; }}
}}
@keyframes orbit-n {{
  0%   {{ opacity: 0.12; }}
  6%   {{ opacity: 1.0;  }}
  40%  {{ opacity: 0.35; }}
  100% {{ opacity: 0.12; }}
}}
@keyframes orbit-e {{
  0%   {{ opacity: 0.12; }}
  6%   {{ opacity: 1.0;  }}
  40%  {{ opacity: 0.35; }}
  100% {{ opacity: 0.12; }}
}}
@keyframes orbit-s {{
  0%   {{ opacity: 0.12; }}
  6%   {{ opacity: 1.0;  }}
  40%  {{ opacity: 0.35; }}
  100% {{ opacity: 0.12; }}
}}
@keyframes orbit-w {{
  0%   {{ opacity: 0.12; }}
  6%   {{ opacity: 1.0;  }}
  40%  {{ opacity: 0.35; }}
  100% {{ opacity: 0.12; }}
}}

/* ── Signal bar animations ── */
@keyframes sig-pulse-1 {{ 0%,100%{{ opacity:0.15; }} 45%{{ opacity:0.80; }} }}
@keyframes sig-pulse-2 {{ 0%,100%{{ opacity:0.15; }} 38%{{ opacity:1.00; }} }}
@keyframes sig-pulse-3 {{ 0%,100%{{ opacity:0.15; }} 55%{{ opacity:0.88; }} }}
@keyframes sig-pulse-4 {{ 0%,100%{{ opacity:0.15; }} 30%{{ opacity:0.72; }} }}
@keyframes sig-pulse-5 {{ 0%,100%{{ opacity:0.15; }} 50%{{ opacity:0.95; }} }}
@keyframes sig-pulse-6 {{ 0%,100%{{ opacity:0.15; }} 42%{{ opacity:0.82; }} }}
@keyframes sig-pulse-7 {{ 0%,100%{{ opacity:0.15; }} 60%{{ opacity:0.70; }} }}
@keyframes sig-pulse-8 {{ 0%,100%{{ opacity:0.15; }} 35%{{ opacity:0.90; }} }}
@keyframes sig-pulse-9 {{ 0%,100%{{ opacity:0.15; }} 48%{{ opacity:0.76; }} }}

.sig-bar {{
  min-width: 2px;
  border-radius: 1px 1px 0 0;
  background: {LV};
  opacity: 0.25;
}}
.sig-bar-1 {{ min-height: 4px;  }}
.sig-bar-2 {{ min-height: 7px;  }}
.sig-bar-3 {{ min-height: 11px; }}
.sig-bar-4 {{ min-height: 15px; }}
.sig-bar-5 {{ min-height: 17px; }}
.sig-bar-6 {{ min-height: 14px; }}
.sig-bar-7 {{ min-height: 10px; }}
.sig-bar-8 {{ min-height: 6px;  }}
.sig-bar-9 {{ min-height: 4px;  }}

.sig-bar-1.playing {{ animation: sig-pulse-1 0.83s ease-in-out infinite 0.00s; }}
.sig-bar-2.playing {{ animation: sig-pulse-2 1.12s ease-in-out infinite 0.20s; }}
.sig-bar-3.playing {{ animation: sig-pulse-3 0.77s ease-in-out infinite 0.08s; }}
.sig-bar-4.playing {{ animation: sig-pulse-4 0.95s ease-in-out infinite 0.35s; }}
.sig-bar-5.playing {{ animation: sig-pulse-5 0.68s ease-in-out infinite 0.12s; }}
.sig-bar-6.playing {{ animation: sig-pulse-6 1.08s ease-in-out infinite 0.28s; }}
.sig-bar-7.playing {{ animation: sig-pulse-7 0.88s ease-in-out infinite 0.05s; }}
.sig-bar-8.playing {{ animation: sig-pulse-8 0.72s ease-in-out infinite 0.42s; }}
.sig-bar-9.playing {{ animation: sig-pulse-9 1.00s ease-in-out infinite 0.17s; }}

/* ── Status indicator labels (MONO/ST/LOUD/MUTE) — GtkLabel, not button ── */
.radio-btn {{
  font-family: "JetBrains Mono", monospace;
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.10em;
  color: {MU};
  background: {B};
  border: 2px solid {SH};
  border-radius: 6px;
  padding: 1px 7px;
  box-shadow: 1px 2px 0 0 {SH};
}}
.radio-btn.playing    {{ color: {SH}; background: {LV}; }}
.radio-btn.st-ind.playing   {{ background: {FM}; color: {SH}; }}
.radio-btn.loud-ind.playing {{ background: {GD}; color: {SH}; }}
.radio-btn.mute-ind.playing {{ background: {RS}; color: {SH}; }}
.radio-btn.mono-ind.playing {{ background: {LV}; color: {SH}; }}
.radio-btn.playing.flicker  {{ opacity: 0.4; }}
.radio-btn.loud-ind.overdrive {{ background: {LV}; color: {SH}; }}

/* ── Orbit ── */
.orbit-grid {{ margin-top: 5px; }}
.orbit-center {{
  min-width: 6px; min-height: 6px;
  border-radius: 3px;
  background: {MU};
  opacity: 0.5;
}}
.orbit-center.playing {{
  background: {LV};
  opacity: 1.0;
  animation: orbit-center-pulse 2.4s ease-in-out infinite;
}}
.orbit-dot {{
  min-width: 4px; min-height: 4px;
  border-radius: 2px;
  background: {LV};
  opacity: 0.12;
}}
.orbit-dot.playing           {{ animation-duration: 1.2s; animation-timing-function: linear; animation-iteration-count: infinite; }}
.orbit-dot-n.playing         {{ animation-name: orbit-n; animation-delay: 0.0s; }}
.orbit-dot-e.playing         {{ animation-name: orbit-e; animation-delay: 0.3s; }}
.orbit-dot-s.playing         {{ animation-name: orbit-s; animation-delay: 0.6s; }}
.orbit-dot-w.playing         {{ animation-name: orbit-w; animation-delay: 0.9s; }}

/* ── Controls tray ── */
.controls {{
  margin-top: 6px;
  background: {S};
  border-radius: 8px;
  border: 2px solid {SH};
  padding: 4px;
  box-shadow: 2px 3px 0 0 {SH};
}}

/* ── Universal paper bubble: all GtkButton widgets ── */
button {{
  background: {O};
  color: {TX};
  border: 2px solid {SH};
  border-radius: 8px;
  padding: 3px 10px;
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  min-width: 0;
  box-shadow: 2px 2px 0 0 {SH};
}}
button:hover {{
  background: {HH};
  color: {TX};
  box-shadow: 1px 1px 0 0 {SH};
}}
button:active {{
  background: {HM};
  box-shadow: none;
}}

/* ── Divider + seam ── */
.divider {{
  background-color: {SH};
  margin: 0;
  min-height: 2px;
}}
.seam {{
  min-height: 1px;
  background: {HL};
  margin: 0;
}}
.seam-shadow {{
  min-height: 1px;
  background: {SH};
  margin: 0;
}}
.mfr-badge {{
  font-family: "JetBrains Mono", monospace;
  font-size: 7px;
  letter-spacing: 0.20em;
  color: {MU};
  padding: 2px 8px 1px 0;
}}

/* ── Toolbar ── */
.toolbar {{
  background: {S};
  padding: 4px 6px;
  border-bottom: 2px solid {SH};
}}
.toolbar entry {{
  background: {B};
  color: {TX};
  border: 2px solid {SH};
  border-radius: 8px;
  padding: 2px 8px;
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  min-height: 0;
  box-shadow: 1px 2px 0 0 {SH};
}}
.toolbar entry:focus {{ border-color: {LV}; }}
.toolbar button.active {{
  background: {LV};
  color: {SH};
  border-color: {SH};
  box-shadow: 1px 2px 0 0 {SH};
}}

/* ── Station list ── */
.station-list {{
  padding: 2px 4px 4px;
  background: {B};
}}
.station-row {{
  font-family: "JetBrains Mono", "Courier New", monospace;
  font-size: 11px;
  letter-spacing: 0.04em;
  color: {SU};
  border-radius: 8px;
  border: 2px solid transparent;
  background: transparent;
  padding: 3px 8px;
  min-height: 0;
}}
.station-row:hover {{
  background: {O};
  color: {TX};
  border-color: {SH};
  box-shadow: 1px 2px 0 0 {SH};
}}
.station-row.active {{
  background: {LV};
  color: {SH};
  border-color: {SH};
  font-weight: 700;
  box-shadow: 2px 3px 0 0 {SH};
}}

/* ── Frequency badge: small teal pill ── */
.freq-badge {{
  color: {SH};
  font-size: 9px;
  font-family: monospace;
  font-weight: 700;
  padding: 1px 5px;
  min-width: 0;
  background: {FM};
  border: 2px solid {SH};
  border-radius: 8px;
  box-shadow: 1px 1px 0 0 {SH};
}}
.freq-badge:hover {{ background: {IR}; box-shadow: none; }}

/* ── Frequency picker in popover ── */
.freq-pick {{
  color: {TX};
  font-size: 10px;
  font-family: monospace;
  padding: 2px 10px;
  background: {O};
  border: 2px solid {SH};
  border-radius: 6px;
  box-shadow: 1px 1px 0 0 {SH};
  min-height: 0;
}}
.freq-pick:hover {{ background: {HH}; box-shadow: none; }}

/* ── Per-row action buttons (edit / delete) ── */
.row-action {{
  background: transparent;
  color: {MU};
  border: 2px solid transparent;
  border-radius: 6px;
  padding: 1px 5px;
  font-size: 11px;
  min-width: 0;
  min-height: 0;
  box-shadow: none;
}}
.row-action:hover {{
  background: {O};
  color: {TX};
  border-color: {SH};
  box-shadow: 1px 1px 0 0 {SH};
}}
.row-action.confirm {{ color: {RS}; }}
.row-action.confirm:hover {{
  background: {RS};
  color: {SH};
  border-color: {SH};
  box-shadow: 1px 1px 0 0 {SH};
}}

/* ── Inline form ── */
.inline-form {{
  background: {S};
  border-bottom: 2px solid {SH};
  padding: 6px 8px;
}}
.inline-form label {{
  font-family: "JetBrains Mono", monospace;
  font-size: 10px;
  color: {SU};
  min-width: 30px;
}}
.form-title {{
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  color: {TX};
  font-weight: bold;
}}
.inline-form entry {{
  background: {B};
  color: {TX};
  border: 2px solid {SH};
  border-radius: 8px;
  padding: 2px 8px;
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  min-height: 0;
  box-shadow: 1px 2px 0 0 {SH};
}}
.inline-form entry:focus {{ border-color: {LV}; }}
.inline-form .cancel:hover {{ background: {RS}; color: {SH}; border-color: {SH}; }}
.form-error {{
  font-family: "JetBrains Mono", monospace;
  font-size: 10px;
  color: {RS};
  font-weight: bold;
}}

/* ── Discover panel ── */
.discover-panel {{
  background: {B};
  padding: 4px;
  border-radius: 0 0 10px 10px;
}}
.discover-entry {{
  background: {S};
  color: {TX};
  border: 2px solid {SH};
  border-radius: 8px;
  padding: 3px 8px;
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  box-shadow: 1px 2px 0 0 {SH};
}}
.discover-entry:focus {{ border-color: {LV}; }}
.discover-status {{
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  color: {MU};
  padding: 6px 4px;
}}
.discover-result {{
  border-bottom: 1px solid rgba({SR}, 0.4);
  padding: 4px;
}}
.discover-name {{
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  color: {TX};
  font-weight: bold;
}}
.discover-meta {{
  font-family: "JetBrains Mono", monospace;
  font-size: 10px;
  color: {SU};
}}
.discover-add {{ background: {FM}; color: {SH}; border-color: {SH}; }}
.discover-add:hover {{ background: {PI}; box-shadow: 1px 1px 0 0 {SH}; }}
.discover-add.added {{ background: {PI}; color: {SH}; }}

/* ── Group/page selector bar ── */
.group-bar {{
  background: {S};
  border: 2px solid {SH};
  border-radius: 8px;
  padding: 3px 4px;
  margin-bottom: 2px;
  box-shadow: 2px 3px 0 0 {SH};
}}
.group-tab {{
  background: transparent;
  color: {MU};
  border: 2px solid transparent;
  border-radius: 6px;
  padding: 1px 7px;
  font-family: "JetBrains Mono", monospace;
  font-size: 10px;
  letter-spacing: 0.06em;
  min-width: 0;
  min-height: 0;
  box-shadow: none;
}}
.group-tab:hover {{
  color: {TX};
  background: {O};
  border-color: {SH};
}}
.group-tab.active {{
  color: {SH};
  background: {LV};
  border-color: {SH};
  font-weight: 700;
  box-shadow: 1px 2px 0 0 {SH};
}}

/* ── Group badge: pale-yellow tag pill ── */
.group-badge {{
  color: {SH};
  font-size: 9px;
  font-family: monospace;
  font-weight: 700;
  padding: 1px 4px;
  min-width: 0;
  background: {PI};
  border: 2px solid {SH};
  border-radius: 8px;
  box-shadow: 1px 1px 0 0 {SH};
}}
.group-badge:hover {{ background: {GD}; box-shadow: none; }}

/* ── Group picker in popover ── */
.group-pick {{
  color: {TX};
  font-size: 10px;
  font-family: monospace;
  padding: 2px 10px;
  background: {O};
  border: 2px solid {SH};
  border-radius: 6px;
  box-shadow: 1px 1px 0 0 {SH};
  min-height: 0;
}}
.group-pick:hover {{ background: {HH}; box-shadow: none; }}

/* ── Collapsed quick-pick bar ── */
.collapsed-quick-bar {{
  padding: 4px 8px 6px;
  background: {S};
  border-top: 2px solid {SH};
}}
.quick-nav {{
  font-family: "JetBrains Mono", monospace;
  font-size: 10px;
  color: {SU};
  background: {O};
  border: 2px solid {SH};
  border-radius: 8px;
  min-width: 26px;
  min-height: 26px;
  padding: 0;
  box-shadow: 1px 2px 0 0 {SH};
}}
.quick-nav:hover {{ background: {HH}; color: {TX}; box-shadow: 1px 1px 0 0 {SH}; }}
.quick-num {{
  font-family: "JetBrains Mono", monospace;
  font-size: 13px;
  font-weight: 700;
  color: {TX};
  background: {O};
  border: 2px solid {SH};
  border-radius: 8px;
  min-width: 34px;
  min-height: 26px;
  padding: 0;
  box-shadow: 1px 2px 0 0 {SH};
}}
.quick-num:hover {{ background: {LV}; color: {SH}; box-shadow: 1px 1px 0 0 {SH}; }}
.quick-num:disabled {{ color: {MU}; background: {B}; box-shadow: none; border-color: {HL}; }}

/* ── Group label readout ── */
.group-label-btn {{
  font-family: "JetBrains Mono", monospace;
  font-size: 8px;
  letter-spacing: 0.18em;
  color: {SU};
  min-width: 48px;
  min-height: 26px;
  padding: 1px 6px;
  background: {B};
  border: 2px solid {SH};
  border-radius: 6px;
  box-shadow: 1px 2px 0 0 {SH};
}}
.group-label-btn:hover {{ color: {TX}; background: {O}; box-shadow: 1px 1px 0 0 {SH}; }}
.controls .group-label-btn {{
  background: {B};
  border: 2px solid {SH};
  color: {SU};
  box-shadow: 1px 2px 0 0 {SH};
}}
.controls .group-label-btn:hover {{ color: {TX}; background: {O}; box-shadow: 1px 1px 0 0 {SH}; }}

/* ── Mode toggle ── */
.controls .mode-toggle {{ color: {LV}; font-size: 16px; }}
.controls .mode-toggle:hover {{ color: {SH}; background: {LV}; }}

/* ── Controls: station num + nav (override global button for size) ── */
.controls .quick-num {{
  font-family: "JetBrains Mono", monospace;
  font-size: 13px;
  font-weight: 700;
  min-width: 0;
  min-height: 26px;
  padding: 0;
}}
.controls .quick-num:disabled {{ color: {MU}; background: {B}; box-shadow: none; }}
.controls .quick-nav {{
  font-family: "JetBrains Mono", monospace;
  font-size: 10px;
  min-width: 22px;
  min-height: 26px;
  padding: 0;
}}
""".encode()

CSS = _build_css(_load_palette())


# ── Daemon comms ───────────────────────────────────────────────────────────────
def daemon_send(msg: dict) -> dict | None:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.settimeout(1.5)
        s.connect(str(CONTROL_SOCK))
        s.sendall((json.dumps(msg) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        return json.loads(data.decode("utf-8", errors="replace"))
    except Exception:
        return None
    finally:
        s.close()


def _get_vol_state() -> tuple[float, bool]:
    """Return (volume_float, muted) from wpctl. Falls back to (0.0, False) on error."""
    try:
        r = subprocess.run(
            ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
            capture_output=True, text=True, timeout=1,
        )
        line = r.stdout.strip()
        parts = line.split()
        vol = float(parts[1]) if len(parts) >= 2 else 0.0
        muted = "[MUTED]" in line
        return vol, muted
    except Exception:
        return 0.0, False


def _get_bt_active() -> bool:
    """Return True if any bluez_output sink node exists in PipeWire."""
    try:
        r = subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=1)
        return "bluez_output" in r.stdout
    except Exception:
        return False


def _mpv_get_property(prop: str):
    """Query a single MPV property directly. Returns the value or None on failure."""
    if not MPV_SOCK.exists():
        return None
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect(str(MPV_SOCK))
            s.sendall((json.dumps({"command": ["get_property", prop]}) + "\n").encode())
            buf = b""
            while not buf.endswith(b"\n"):
                chunk = s.recv(4096)
                if not chunk:
                    break
                buf += chunk
        if buf.strip():
            resp = json.loads(buf.decode())
            if resp.get("error") == "success":
                return resp.get("data")
    except Exception:
        pass
    return None


def _get_stream_bitrate() -> int | None:
    """Return stream bitrate in kbps from MPV audio-bitrate property, or None."""
    # Query audio-bitrate as a direct MPV property (returns bps as float)
    val = _mpv_get_property("audio-bitrate")
    if val is not None:
        try:
            v = int(float(val))
            return v // 1000 if v > 1000 else v
        except (ValueError, TypeError):
            pass
    # Fallback: icy-br tag in stream metadata (some stations embed it)
    meta = _mpv_metadata()
    if meta:
        for key in ("icy-br", "bitrate"):
            raw = meta.get(key)
            if raw:
                try:
                    return int(float(raw))
                except (ValueError, TypeError):
                    pass
    return None


def _get_stream_channels() -> int | None:
    """Return channel count from MPV (1 = mono, 2 = stereo), or None."""
    val = _mpv_get_property("audio-params/channel-count")
    if val is not None:
        try:
            return int(val)
        except (ValueError, TypeError):
            pass
    return None


def _mpv_metadata() -> dict | None:
    """Query the MPV IPC socket and return the full metadata dict, or None on failure."""
    if not MPV_SOCK.exists():
        return None
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect(str(MPV_SOCK))
            s.sendall((json.dumps({"command": ["get_property", "metadata"]}) + "\n").encode())
            buf = b""
            while not buf.endswith(b"\n"):
                chunk = s.recv(4096)
                if not chunk:
                    break
                buf += chunk
        if buf.strip():
            resp = json.loads(buf.decode())
            if resp.get("error") == "success":
                return resp.get("data") or {}
    except Exception:
        pass
    return None


def _playerctl_track() -> tuple[str | None, str | None]:
    """Last-resort fallback: read artist/title from playerctl MPRIS interface."""
    try:
        def _pc(field: str) -> str | None:
            r = subprocess.run(
                ["playerctl", "-p", "sqlch", "metadata", field],
                capture_output=True, text=True, timeout=2,
            )
            return r.stdout.strip() or None
        artist = _pc("artist")
        title  = _pc("title")
        # Some streams pack everything into title even via MPRIS
        if not artist and title and " - " in title:
            artist, title = title.split(" - ", 1)
            artist = artist.strip() or None
            title  = title.strip()  or None
        return html.unescape(artist) if artist else None, html.unescape(title) if title else None
    except Exception:
        return None, None


def get_icy_track() -> tuple[str | None, str | None]:
    """Return (artist, track) from the best available metadata source.

    Priority:
      1. Separate artist + title fields in MPV metadata (set by some streams)
      2. icy-title / title field split on ' - ' (space-dash-space, much safer)
      3. icy-title split on bare '-' as last MPV-side attempt
      4. playerctl MPRIS fallback (separate fields, already parsed by MPV MPRIS plugin)
    """
    meta = _mpv_metadata()
    if meta is not None:
        # Priority 1 — streams that set artist/title as distinct tags
        artist = (meta.get("artist") or meta.get("Artist") or "").strip() or None
        title  = (meta.get("title")  or meta.get("Title")  or "").strip() or None
        if artist and title:
            return html.unescape(artist), html.unescape(title)

        # Priority 2 — icy-title or title, split on ' - ' (space-padded, safer)
        raw = (meta.get("icy-title") or meta.get("title") or "").strip()
        if raw and " - " in raw:
            a, t = raw.split(" - ", 1)
            return html.unescape(a.strip()) or None, html.unescape(t.strip()) or None

        # Priority 3 — bare '-' split (original behaviour, last MPV attempt)
        if raw and "-" in raw:
            a, t = raw.split("-", 1)
            return html.unescape(a.strip()) or None, html.unescape(t.strip()) or None

    # Priority 4 — playerctl MPRIS (separate fields, compositor-managed)
    return _playerctl_track()


def get_icy_genre() -> str | None:
    """Return the stream-native genre from ICY headers if the station sends one."""
    meta = _mpv_metadata()
    if meta:
        return (meta.get("icy-genre") or meta.get("genre") or "").strip() or None
    return None


def get_enriched_meta(artist: str, track: str) -> tuple[str, str]:
    """Return (album_title, 'year - genre') from enriched cache.

    Falls back to the studio version's metadata when no entry exists for a
    live/bootleg/demo track, then to the stream-native icy-genre.
    """
    try:
        enriched = json.loads(ENRICHED_JSON.read_text())
        norm = lambda s: " ".join(s.lower().split())
        entry = enriched.get(f"{norm(artist)}::{norm(track)}")
        if not entry:
            base_track, qualifier = _strip_live_qualifier(track)
            if qualifier and base_track != track:
                entry = enriched.get(f"{norm(artist)}::{norm(base_track)}")
        if entry:
            album = entry.get("album") or ""
            year  = str(entry["year"]) if entry.get("year") else ""
            genre = (entry.get("genres") or [""])[0]
            sub   = "  -  ".join(p for p in [year, genre] if p)
            return album, sub
    except Exception:
        pass
    # No Spotify cache — try the raw ICY genre tag from the stream
    icy_genre = get_icy_genre()
    return "", icy_genre or ""


def get_cover_info(artist: str, track: str) -> tuple[Path | None, str | None]:
    """Return (cached_path, cover_url), with studio-version fallback for live/bootleg/demo tracks.

    When the exact track has no cover URL in the enriched cache, strips the live/demo
    qualifier and retries with the base studio title so the album art still shows.
    """
    try:
        enriched = json.loads(ENRICHED_JSON.read_text())
        norm = lambda s: " ".join(s.lower().split())

        entry = enriched.get(f"{norm(artist)}::{norm(track)}")
        if entry:
            result = _resolve_cover_entry(entry)
            if result[1]:  # cover URL exists (path may still need downloading)
                return result

        # No art for this exact track — try the studio version
        base_track, qualifier = _strip_live_qualifier(track)
        if qualifier and base_track != track:
            studio = enriched.get(f"{norm(artist)}::{norm(base_track)}")
            if studio:
                result = _resolve_cover_entry(studio)
                if result[1]:
                    return result
    except Exception:
        pass
    return None, None


def get_station_list() -> list[dict]:
    try:
        result = subprocess.run(
            ["sqlch", "list"],
            capture_output=True, text=True, timeout=3
        )
        lib = _load_library()
        by_id = {s["id"]: s for s in lib["stations"]}

        stations = []
        for line in result.stdout.strip().splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split(None, 1)
            sid  = parts[0]
            name = parts[1] if len(parts) > 1 else sid
            st    = by_id.get(sid, {})
            freq  = st.get("frequency")
            group = st.get("category") or _auto_group(freq)
            stations.append({"id": sid, "name": name, "frequency": freq, "group": group})
        return stations
    except Exception:
        return []


# ── Library helpers (replicate library.py logic without importing the package) ─
def _normalize_id(name: str) -> str:
    s = name.lower().strip()
    s = re.sub(r"[^\w\s-]", "", s)
    s = re.sub(r"[\s_-]+", "-", s)
    return s.strip("-")


def _load_library() -> dict:
    try:
        return json.loads(LIBRARY_JSON.read_text())
    except Exception:
        return {"version": 1, "stations": []}


def _save_library(lib: dict):
    LIBRARY_JSON.parent.mkdir(parents=True, exist_ok=True)
    tmp = LIBRARY_JSON.with_suffix(".tmp")
    tmp.write_text(json.dumps(lib, indent=2, sort_keys=True))
    tmp.replace(LIBRARY_JSON)


def library_add_url(name: str, url: str) -> str | None:
    """Add station by name+URL directly. Returns error string or None."""
    if not name:
        return "name is required"
    if not url:
        return "url is required"
    sid = _normalize_id(name)
    lib = _load_library()
    if any(s["id"] == sid for s in lib["stations"]):
        return f"id '{sid}' already exists — rename station"
    freq = _assign_frequency(sid)
    station = {
        "id": sid, "name": name, "url": url,
        "category": _auto_group(freq), "tags": [], "notes": None,
        "frequency": freq,
        "added_at": int(time.time()), "last_played": None, "play_count": 0,
        "source": {"type": "manual", "origin": "user"},
        "stream": {"bitrate": None, "codec": None, "country": None,
                   "last_checked": None, "validated": False},
    }
    lib["stations"].append(station)
    _save_library(lib)
    return None


def library_update(station_id: str, name: str, url: str | None = None) -> str | None:
    """Update station name (and optionally url). Returns error string or None."""
    if not name:
        return "name is required"
    lib = _load_library()
    for i, st in enumerate(lib["stations"]):
        if st["id"] == station_id:
            st["name"] = name
            if url:
                st["url"] = url
            lib["stations"][i] = st
            _save_library(lib)
            return None
    return f"station '{station_id}' not found"


def library_remove(station_id: str) -> str | None:
    """Remove station. Returns error string or None."""
    lib = _load_library()
    station = next((s for s in lib["stations"] if s["id"] == station_id), None)
    if station is None:
        return f"station '{station_id}' not found"
    _release_frequency(station_id, station.get("frequency"))
    lib["stations"] = [s for s in lib["stations"] if s["id"] != station_id]
    _save_library(lib)
    return None


def library_set_frequency(station_id: str, new_freq: str) -> str | None:
    """Manually set a station's frequency. Manages pool accordingly. Returns error or None."""
    lib = _load_library()
    for i, st in enumerate(lib["stations"]):
        if st["id"] == station_id:
            old_freq = st.get("frequency")
            if old_freq == new_freq:
                return None
            # Return old pool frequency
            if old_freq:
                _release_frequency(station_id, old_freq)
            # Remove new freq from pool if it's there
            if new_freq in _PHILLY_FREQ_POOL:
                available = _load_freq_pool()
                if new_freq in available:
                    available.remove(new_freq)
                    _save_freq_pool(available)
            st["frequency"] = new_freq
            lib["stations"][i] = st
            _save_library(lib)
            return None
    return f"station '{station_id}' not found"


def library_set_group(station_id: str, group: str) -> str | None:
    """Set a station's page group (category). Returns error or None."""
    lib = _load_library()
    for i, st in enumerate(lib["stations"]):
        if st["id"] == station_id:
            st["category"] = group
            lib["stations"][i] = st
            _save_library(lib)
            return None
    return f"station '{station_id}' not found"


# ── Frequency cache helpers ───────────────────────────────────────────────────
def _load_freq_pool() -> list[str]:
    """Return the list of pool frequencies still available for assignment.

    On first call the cache is bootstrapped from _PHILLY_FREQ_POOL minus any
    pool frequencies already assigned to library stations, so existing stations
    aren't double-assigned.  Known-frequency stations are never in the pool.
    """
    if FREQ_CACHE_JSON.exists():
        try:
            return json.loads(FREQ_CACHE_JSON.read_text()).get("available", [])
        except Exception:
            pass
    # Bootstrap: exclude frequencies already held by library stations
    lib = _load_library()
    assigned = {s.get("frequency") for s in lib["stations"] if s.get("frequency")}
    available = [f for f in _PHILLY_FREQ_POOL if f not in assigned]
    _save_freq_pool(available)
    return available


def _save_freq_pool(available: list[str]):
    FREQ_CACHE_JSON.parent.mkdir(parents=True, exist_ok=True)
    tmp = FREQ_CACHE_JSON.with_suffix(".tmp")
    tmp.write_text(json.dumps({"available": available}, indent=2))
    tmp.replace(FREQ_CACHE_JSON)


def _assign_frequency(station_id: str) -> str | None:
    """Return the frequency to assign to a station being added.

    Known stations get their real Philly frequency.  Others draw the next
    available frequency from the pool (removing it until the station is deleted).
    Returns None if the pool is exhausted and the station has no known frequency.
    """
    if station_id in _KNOWN_FREQUENCIES:
        return _KNOWN_FREQUENCIES[station_id]
    available = _load_freq_pool()
    if not available:
        return None
    freq = available.pop(0)
    _save_freq_pool(available)
    return freq


def _release_frequency(station_id: str, frequency: str | None):
    """Return a pool frequency when a station is deleted.

    Known-frequency stations are skipped — their frequency is never in the pool.
    """
    if not frequency or station_id in _KNOWN_FREQUENCIES:
        return
    if frequency not in _PHILLY_FREQ_POOL:
        return
    available = _load_freq_pool()
    if frequency not in available:
        available.append(frequency)
        _save_freq_pool(available)


def _auto_group(frequency: str | None) -> str:
    """Assign a default page group based on frequency type."""
    if frequency is None:
        return "INT1"
    if "AM" in frequency:
        return "AM1"
    return "FM1"


# ── RadioBrowser discovery helpers ────────────────────────────────────────────
_RB_API = "https://de1.api.radio-browser.info/json/stations/search"
_RB_MIRRORS = [
    "https://de1.api.radio-browser.info",
    "https://nl1.api.radio-browser.info",
    "https://at1.api.radio-browser.info",
]

def search_radiobrowser(query: str, limit: int = 40) -> list[dict]:
    """Search RadioBrowser directly via HTTP. Returns list of result dicts."""
    import urllib.parse
    params = urllib.parse.urlencode({
        "name": query, "limit": limit,
        "hidebroken": "true", "order": "votes", "reverse": "true",
    })
    for mirror in _RB_MIRRORS:
        try:
            req = urllib.request.Request(
                f"{mirror}/json/stations/search?{params}",
                headers={"User-Agent": "sqlch-popup/1.0"},
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read())
            results = []
            for station in data:
                url = station.get("url_resolved") or station.get("url", "")
                if not url:
                    continue
                results.append({
                    "name":    station.get("name", "?").strip(),
                    "url":     url,
                    "country": station.get("country", "-"),
                    "codec":   station.get("codec", "-"),
                    "bitrate": str(station.get("bitrate") or "-"),
                    "tags":    station.get("tags", ""),
                })
            return results
        except Exception:
            continue
    return []


_search_cache: list[dict] = []


def run_search(query: str) -> list[dict]:
    """Search RadioBrowser, index results, cache for run_add_from_search."""
    global _search_cache
    raw = search_radiobrowser(query)
    _search_cache = [{**r, "index": i + 1} for i, r in enumerate(raw)]
    return _search_cache


def run_add_from_search(number: int) -> str | None:
    """Add station #number from last run_search result. Returns error or None."""
    entry = next((r for r in _search_cache if r["index"] == number), None)
    if entry is None:
        return f"result #{number} not found"
    return library_add_url(entry["name"], entry["url"])


# ── Scrolling ticker label (monospace-safe character-based animation) ─────────
class MarqueeLabel(Gtk.Label):
    """Scrolls text horizontally when it exceeds the visible character budget."""
    _STEP_MS    = 250  # ms between each character advance
    _PAUSE      = 35   # steps to hold at start before scrolling begins
    _LOOP_PAUSE = 20   # steps to hold after completing one full loop (5 s)
    _SEP        = "   ·   "

    def __init__(self, chars: int = 28):
        super().__init__()
        self._chars = chars
        self._full  = ""
        self._loop  = ""
        self._pos   = 0
        self._hold  = 0
        self._tid: int | None = None

    def set_marquee(self, text: str):
        text = text or ""
        if text == self._full:
            return   # Don't restart the ticker — poll fires every 1.5 s
        self._stop()
        self._full = text
        if len(self._full) <= self._chars:
            self.set_label(self._full)
        else:
            self.set_label(self._full[:self._chars])
            self._loop = self._full + self._SEP
            self._pos  = 0
            self._hold = self._PAUSE
            self._tid  = GLib.timeout_add(self._STEP_MS, self._tick)

    def _tick(self) -> bool:
        if self._hold > 0:
            self._hold -= 1
            return True
        doubled = self._loop + self._loop
        self.set_label(doubled[self._pos : self._pos + self._chars])
        self._pos += 1
        if self._pos >= len(self._loop):
            self._pos = 0
            self._hold = self._LOOP_PAUSE  # pause at original position before looping
        return True

    def _stop(self):
        if self._tid is not None:
            GLib.source_remove(self._tid)
            self._tid = None

    def set_visible(self, visible: bool):
        if not visible:
            self._stop()
        super().set_visible(visible)


# ── Static flicker helper ─────────────────────────────────────────────────────
class StaticFlicker:
    """Adds irregular dim-flicker to a GTK widget by toggling the 'flicker' CSS class.

    Schedules random on/off intervals to simulate radio static. Only runs while
    active; call start()/stop() to control. All GLib calls happen on the main thread
    via the timeout mechanism — safe to call stop() from any thread.
    """
    _ON_MS  = (40, 120)   # how long a flicker-dim lasts (ms)
    _OFF_MS = (300, 900)  # gap between flickers (ms)

    def __init__(self, widget: Gtk.Widget):
        self._widget = widget
        self._tid: int | None = None

    def start(self):
        if self._tid is None:
            self._tid = GLib.timeout_add(random.randint(*self._OFF_MS), self._go_dim)

    def stop(self):
        if self._tid is not None:
            GLib.source_remove(self._tid)
            self._tid = None
        self._widget.remove_css_class("flicker")

    def _go_dim(self) -> bool:
        self._widget.add_css_class("flicker")
        self._tid = GLib.timeout_add(random.randint(*self._ON_MS), self._go_bright)
        return False

    def _go_bright(self) -> bool:
        self._widget.remove_css_class("flicker")
        self._tid = GLib.timeout_add(random.randint(*self._OFF_MS), self._go_dim)
        return False


# ── Now Playing widget ─────────────────────────────────────────────────────────
class NowPlaying(Gtk.Box):
    def __init__(self, on_collapse=None, on_station_select=None,
                 on_prev_group=None, on_next_group=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.add_css_class("now-playing")
        self._on_collapse_cb = on_collapse

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.append(row)

        self._art = Gtk.Image()
        self._art.set_pixel_size(ART_SIZE)
        self._art.set_visible(False)
        self._art_frame = Gtk.Box()
        self._art_frame.add_css_class("art-panel")
        self._art_frame.set_valign(Gtk.Align.CENTER)
        self._art_frame.append(self._art)
        row.append(self._art_frame)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        info.add_css_class("info-panel")
        info.set_hexpand(True)
        info.set_vexpand(True)
        info.set_valign(Gtk.Align.FILL)
        row.append(info)

        top_spacer = Gtk.Box()
        top_spacer.set_vexpand(True)
        info.append(top_spacer)

        self._name_label = MarqueeLabel(chars=26)
        self._name_label.add_css_class("station-name")
        self._name_label.set_halign(Gtk.Align.START)
        self._name_label.set_marquee("—")
        name_bar = Gtk.Box()
        name_bar.add_css_class("display-bar")
        name_bar.set_hexpand(True)
        name_bar.append(self._name_label)
        info.append(name_bar)

        self._track_label = MarqueeLabel(chars=34)
        self._track_label.add_css_class("track-info")
        self._track_label.set_halign(Gtk.Align.START)
        self._track_bar = Gtk.Box()
        self._track_bar.add_css_class("display-bar")
        self._track_bar.set_hexpand(True)
        self._track_bar.set_visible(False)
        self._track_bar.append(self._track_label)
        info.append(self._track_bar)

        bottom_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        bottom_row.add_css_class("indicator-panel")
        bottom_row.set_valign(Gtk.Align.CENTER)

        orbit = Gtk.Grid()
        orbit.add_css_class("orbit-grid")
        orbit.set_row_spacing(3)
        orbit.set_column_spacing(3)
        orbit.set_valign(Gtk.Align.CENTER)

        self._orbit_center = Gtk.Box()
        self._orbit_center.add_css_class("orbit-center")
        orbit.attach(self._orbit_center, 1, 1, 1, 1)

        self._orbit_dots = []
        for cls, col, row in [("orbit-dot-n", 1, 0), ("orbit-dot-e", 2, 1),
                               ("orbit-dot-s", 1, 2), ("orbit-dot-w", 0, 1)]:
            dot = Gtk.Box()
            dot.add_css_class("orbit-dot")
            dot.add_css_class(cls)
            self._orbit_dots.append(dot)
            orbit.attach(dot, col, row, 1, 1)

        bottom_row.append(orbit)

        self._meta_sub = Gtk.Label()   # kept so existing set_text() calls are no-ops
        self._meta_sub.add_css_class("meta-sub")

        # Signal bars + ST indicator fill the space where meta-sub was
        sig_area = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        sig_area.set_hexpand(True)
        sig_area.set_halign(Gtk.Align.CENTER)
        sig_area.set_valign(Gtk.Align.CENTER)

        # Receiver button strip: unlit buttons flank the lit indicators + bars
        # Layout: MONO · ST · [bars] · LOUD · MUTE
        # NOTE: _radio_indicators drives _set_eq_playing animations (orbit center etc).
        # MONO/ST/LOUD/MUTE indicators are intentionally NOT in this list (lit=False)
        # so _set_eq_playing doesn't clobber update_indicators state.
        # Do not change any of these four to lit=True without updating _set_eq_playing.
        self._radio_indicators = []

        def _radio_btn(text, lit=False, extra_class=None):
            lbl = Gtk.Label(label=text)
            lbl.add_css_class("radio-btn")
            if extra_class:
                lbl.add_css_class(extra_class)
            lbl.set_valign(Gtk.Align.FILL)
            if lit:
                self._radio_indicators.append(lbl)
            return lbl

        self._mono_ind = _radio_btn("MONO", lit=False, extra_class="mono-ind")
        sig_area.append(self._mono_ind)
        self._mono_flicker = StaticFlicker(self._mono_ind)

        self._st_ind = _radio_btn("ST", lit=False, extra_class="st-ind")
        sig_area.append(self._st_ind)
        self._st_flicker = StaticFlicker(self._st_ind)

        bars_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=1)
        bars_box.set_valign(Gtk.Align.END)
        bars_box.set_margin_start(3)
        bars_box.set_margin_end(3)
        self._signal_bars = []
        for i in range(9):
            bar = Gtk.Box()
            bar.add_css_class("sig-bar")
            bar.add_css_class(f"sig-bar-{i + 1}")
            bar.set_valign(Gtk.Align.END)
            bars_box.append(bar)
            self._signal_bars.append(bar)
        sig_area.append(bars_box)

        self._loud_ind = _radio_btn("LOUD", lit=False, extra_class="loud-ind")
        sig_area.append(self._loud_ind)
        self._mute_ind = _radio_btn("MUTE", lit=False, extra_class="mute-ind")
        sig_area.append(self._mute_ind)
        bottom_row.append(sig_area)

        info.append(bottom_row)

        bot_spacer = Gtk.Box()
        bot_spacer.set_vexpand(True)
        info.append(bot_spacer)

        controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        controls.add_css_class("controls")
        self.append(controls)

        # Stack fills the whole controls row; toggle lives inside each page
        # so all buttons share the same box and size equally.
        self._ctrl_mode = "transport"
        self._ctrl_stack = Gtk.Stack()
        self._ctrl_stack.set_hexpand(True)
        self._ctrl_stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self._ctrl_stack.set_transition_duration(120)
        controls.append(self._ctrl_stack)

        # -- Transport page: [●] [⏮] [⏸] [⏹] [⏭] [◈] [▼] --
        transport_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)

        self._toggle_mode_btn = Gtk.Button(label="●")
        self._toggle_mode_btn.add_css_class("mode-toggle")
        self._toggle_mode_btn.set_tooltip_text("Switch to station presets")
        self._toggle_mode_btn.connect("clicked", self._on_toggle_mode)
        self._toggle_mode_btn.set_hexpand(True)
        transport_box.append(self._toggle_mode_btn)

        self._btn_prev = self._make_btn("⏮", lambda *_: daemon_send({"cmd": "prev"}))
        self._btn_play = self._make_btn("⏸",  self._on_play_pause)
        self._btn_stop = self._make_btn("⏹",  lambda *_: daemon_send({"cmd": "stop"}))
        self._btn_next = self._make_btn("⏭", lambda *_: daemon_send({"cmd": "next"}))
        self._btn_meta = self._make_btn("◈",  self._on_meta_click)
        self._btn_meta.set_tooltip_text("Fetch metadata & album art")
        self._btn_collapse = self._make_btn("▼", self._on_collapse_click)
        self._btn_collapse.set_tooltip_text("Collapse station list")
        for b in [self._btn_prev, self._btn_play, self._btn_stop, self._btn_next,
                  self._btn_meta, self._btn_collapse]:
            b.set_hexpand(True)
            transport_box.append(b)
        self._ctrl_stack.add_named(transport_box, "transport")

        # -- Station page: [●] [◀] [ALL] [1]…[6] [▶] --
        station_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        self._station_ids: list[str] = []
        self._quick_btns: list[Gtk.Button] = []
        self._on_station_select_cb = on_station_select
        self._on_prev_group_cb = on_prev_group
        self._on_next_group_cb = on_next_group

        station_toggle = Gtk.Button(label="●")
        station_toggle.add_css_class("mode-toggle")
        station_toggle.set_tooltip_text("Switch to transport controls")
        station_toggle.connect("clicked", self._on_toggle_mode)
        station_toggle.set_hexpand(True)
        station_box.append(station_toggle)

        self._quick_left = Gtk.Button(label="◀")
        self._quick_left.add_css_class("quick-nav")
        if on_prev_group:
            self._quick_left.connect("clicked", lambda _: on_prev_group())
        station_box.append(self._quick_left)

        self._quick_group_label = Gtk.Button(label="ALL")
        self._quick_group_label.add_css_class("group-label-btn")
        self._quick_group_label.set_halign(Gtk.Align.CENTER)
        station_box.append(self._quick_group_label)

        for i in range(1, 7):
            btn = Gtk.Button(label=str(i))
            btn.add_css_class("quick-num")
            btn.connect("clicked", self._on_quick_click, i - 1)
            btn.set_sensitive(False)
            btn.set_hexpand(True)
            station_box.append(btn)
            self._quick_btns.append(btn)

        self._quick_right = Gtk.Button(label="▶")
        self._quick_right.add_css_class("quick-nav")
        if on_next_group:
            self._quick_right.connect("clicked", lambda _: on_next_group())
        station_box.append(self._quick_right)

        self._ctrl_stack.add_named(station_box, "stations")

        self._current_id: str | None = None
        self._art_fetching: str | None = None   # URL currently being fetched
        self._logo_fetching: str | None = None  # station_id whose logo is being fetched

    def _on_collapse_click(self, *_):
        if self._on_collapse_cb:
            self._on_collapse_cb()

    def set_collapsed(self, collapsed: bool):
        self._btn_collapse.set_label("▲" if collapsed else "▼")
        self._btn_collapse.set_tooltip_text(
            "Expand station list" if collapsed else "Collapse station list"
        )

    def _on_toggle_mode(self, *_):
        if self._ctrl_mode == "transport":
            self._ctrl_mode = "stations"
            self._ctrl_stack.set_visible_child_name("stations")
        else:
            self._ctrl_mode = "transport"
            self._ctrl_stack.set_visible_child_name("transport")

    def update_stations(self, station_ids: list[str], station_names: list[str] | None = None):
        self._station_ids = station_ids
        for i, btn in enumerate(self._quick_btns):
            has = i < len(station_ids)
            btn.set_sensitive(has)
            btn.set_tooltip_text(station_names[i] if has and station_names else None)

    def set_quick_group(self, group: str | None):
        self._quick_group_label.set_label(group or "ALL")

    def update_quick_nav_tooltips(self, prev_group: str | None, next_group: str | None):
        self._quick_left.set_tooltip_text(f"Prev: {prev_group or 'ALL'}")
        self._quick_right.set_tooltip_text(f"Next: {next_group or 'ALL'}")

    def _on_quick_click(self, _, idx: int):
        if idx < len(self._station_ids) and self._on_station_select_cb:
            self._on_station_select_cb(self._station_ids[idx])

    def _make_btn(self, label: str, handler) -> Gtk.Button:
        b = Gtk.Button(label=label)
        b.connect("clicked", handler)
        return b

    def _on_play_pause(self, *_):
        daemon_send({"cmd": "pause"})

    def _on_meta_click(self, *_):
        """Enrich current track metadata and download album art."""
        artist, track = get_icy_track()
        if not artist or not track:
            return
        self._btn_meta.set_label("…")
        self._btn_meta.set_sensitive(False)
        threading.Thread(
            target=self._bg_meta, args=(artist, track), daemon=True
        ).start()

    def _bg_meta(self, artist: str, track: str):
        """Background: enrich → download art → update UI."""
        result = run_enrich(artist, track)
        cover_url = (result or {}).get("cover")
        cover_path = _download_cover(cover_url) if cover_url else None
        GLib.idle_add(self._finish_meta, cover_path)

    def _finish_meta(self, cover_path: Path | None):
        self._btn_meta.set_label("◈")
        self._btn_meta.set_sensitive(True)
        if cover_path:
            self._show_art(cover_path)
        return False

    def get_current_id(self) -> str | None:
        return self._current_id

    def _set_eq_playing(self, playing: bool):
        for dot in self._orbit_dots:
            if playing:
                dot.add_css_class("playing")
            else:
                dot.remove_css_class("playing")
        for bar in self._signal_bars:
            if playing:
                bar.add_css_class("playing")
            else:
                bar.remove_css_class("playing")
        if playing:
            self._orbit_center.add_css_class("playing")
            for ind in self._radio_indicators:
                ind.add_css_class("playing")
        else:
            self._orbit_center.remove_css_class("playing")
            for ind in self._radio_indicators:
                ind.remove_css_class("playing")
            # Clear all indicator-specific state that update_indicators manages
            self._loud_ind.remove_css_class("playing")
            self._loud_ind.remove_css_class("overdrive")
            self._mono_ind.remove_css_class("playing")
            self._mono_flicker.stop()
            self._st_ind.remove_css_class("playing")
            self._st_flicker.stop()
            self._mute_ind.remove_css_class("playing")

    def update_indicators(self, bitrate: int | None, vol: float, muted: bool, bt_active: bool, playing: bool = False, channels: int | None = None):
        """Update MONO/ST/LOUD/MUTE indicator lights from system state."""
        # MUTE overrides everything
        if muted:
            self._mute_ind.add_css_class("playing")
            self._mono_ind.remove_css_class("playing")
            self._mono_flicker.stop()
            self._st_ind.remove_css_class("playing")
            self._st_flicker.stop()
            self._loud_ind.remove_css_class("playing")
            self._loud_ind.remove_css_class("overdrive")
            return

        self._mute_ind.remove_css_class("playing")

        # MONO vs ST: prefer channel count (definitive), fall back to bitrate heuristic
        if channels is not None:
            is_stereo = channels >= 2
        elif bitrate is not None:
            is_stereo = bitrate >= 128
        else:
            is_stereo = None

        if is_stereo is True:
            self._st_ind.add_css_class("playing")
            self._st_flicker.start()
            self._mono_ind.remove_css_class("playing")
            self._mono_flicker.stop()
        elif is_stereo is False:
            self._mono_ind.add_css_class("playing")
            self._mono_flicker.start()
            self._st_ind.remove_css_class("playing")
            self._st_flicker.stop()
        else:
            self._mono_ind.remove_css_class("playing")
            self._mono_flicker.stop()
            self._st_ind.remove_css_class("playing")
            self._st_flicker.stop()

        # LOUD: only active when something is playing
        self._loud_ind.remove_css_class("playing")
        self._loud_ind.remove_css_class("overdrive")
        if playing:
            if bt_active or vol > 1.0:
                self._loud_ind.add_css_class("overdrive")
            elif vol >= 0.65:
                self._loud_ind.add_css_class("playing")

    def _set_art_visible(self, v: bool):
        self._art.set_visible(v)   # frame always stays in layout

    def _show_art(self, path: Path):
        try:
            pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                str(path), ART_SIZE, ART_SIZE, True)
            self._art.set_from_pixbuf(pb)
            self._set_art_visible(True)
        except Exception:
            self._set_art_visible(False)

    def _start_art_fetch(self, url: str):
        """Kick off a background download for a cover URL if not already fetching it."""
        if url == self._art_fetching:
            return
        self._art_fetching = url
        threading.Thread(target=self._bg_art, args=(url,), daemon=True).start()

    def _bg_art(self, url: str):
        path = _download_cover(url)
        GLib.idle_add(self._finish_art, url, path)

    def _finish_art(self, url: str, path: Path | None):
        if url == self._art_fetching and path:
            self._show_art(path)
        self._art_fetching = None
        return False

    def _try_station_logo(self, station_id: str, station_name: str, station_url: str | None = None):
        """Show cached station logo or kick off a background fetch. Falls back to hidden art."""
        logo = _logo_path(station_id)
        if logo.exists():
            self._show_art(logo)
        elif station_id != self._logo_fetching:
            self._set_art_visible(False)
            self._logo_fetching = station_id
            threading.Thread(
                target=self._bg_logo, args=(station_id, station_name, station_url), daemon=True
            ).start()
        else:
            self._set_art_visible(False)

    def _bg_logo(self, station_id: str, station_name: str, station_url: str | None):
        path = _download_logo(station_id, station_name, station_url)
        GLib.idle_add(self._finish_logo, station_id, path)

    def _finish_logo(self, station_id: str, path: Path | None):
        if station_id == self._logo_fetching:
            self._logo_fetching = None
            if path and station_id == self._current_id:
                self._show_art(path)
        return False

    def update(self, resp: dict | None, icy: tuple[str | None, str | None] | None = None):
        if not resp or not resp.get("ok"):
            self._name_label.set_marquee("daemon offline")
            self._track_bar.set_visible(False)
            self._meta_sub.set_text("")
            self._set_art_visible(False)
            self._set_eq_playing(False)
            self._current_id = None
            return

        current = resp.get("current")
        status  = resp.get("status", "")
        paused  = "paused" in status.lower()
        self._btn_play.set_label("▶" if paused else "⏸")

        if not current or not isinstance(current, dict):
            self._name_label.set_marquee("idle")
            self._track_bar.set_visible(False)
            self._meta_sub.set_text("")
            self._set_art_visible(False)
            self._set_eq_playing(False)
            self._current_id = None
            return

        self._set_eq_playing(not paused)

        item = current.get("item", {})
        name = item.get("name", "Unknown")
        station_id = item.get("id") or ""
        self._current_id = station_id or name
        lib = _load_library()
        freq = next((s.get("frequency") for s in lib["stations"] if s["id"] == station_id), None)
        self._name_label.set_marquee(f"{freq}  ·  {name}" if freq else name)

        artist, track = icy if icy is not None else get_icy_track()
        if artist and track:
            _, qualifier = _strip_live_qualifier(track)
            album, year_genre = get_enriched_meta(artist, track)
            track_text = f"{artist}  —  {track}"
            if album:
                track_text += f"  —  {album}"
            if qualifier:
                track_text = f"[{qualifier}]  {track_text}"
            self._track_label.set_marquee(track_text)
            self._track_bar.set_visible(True)
            self._meta_sub.set_text(year_genre)
            cover_path, cover_url = get_cover_info(artist, track)
            if cover_path:
                self._show_art(cover_path)
            elif cover_url:
                self._set_art_visible(False)
                self._start_art_fetch(cover_url)
            else:
                self._set_art_visible(False)
        else:
            self._track_bar.set_visible(False)
            self._meta_sub.set_text("")
            self._set_art_visible(False)


# ── Collapsed quick-pick number bar ───────────────────────────────────────────
class CollapsedQuickBar(Gtk.Box):
    """Six numbered buttons (1-6) shown when the station list is collapsed.
    Each button maps to the nth visible station in the current tab.
    ◀/▶ nav buttons on each side cycle through station groups.
    A thin label strip above the buttons shows the active group name."""
    def __init__(self, on_select, on_prev_group=None, on_next_group=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add_css_class("collapsed-quick-bar")
        self.set_halign(Gtk.Align.FILL)
        self._on_select = on_select
        self._station_ids: list[str] = []
        self._btns: list[Gtk.Button] = []

        # ── Nav + number buttons row ─────────────────────────────────────────
        nav_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        self.append(nav_row)

        self._left_nav = Gtk.Button(label="◀")
        self._left_nav.add_css_class("quick-nav")
        if on_prev_group:
            self._left_nav.connect("clicked", lambda _: on_prev_group())
        nav_row.append(self._left_nav)

        # ── Group indicator label (inline, after ◀, before number buttons) ──
        self._group_label = Gtk.Button(label="ALL")
        self._group_label.add_css_class("group-label-btn")
        self._group_label.set_halign(Gtk.Align.CENTER)
        self._group_label.set_hexpand(False)
        nav_row.append(self._group_label)

        for i in range(1, 7):
            btn = Gtk.Button(label=str(i))
            btn.add_css_class("quick-num")
            btn.connect("clicked", self._on_click, i - 1)
            btn.set_sensitive(False)
            btn.set_hexpand(True)
            nav_row.append(btn)
            self._btns.append(btn)

        self._right_nav = Gtk.Button(label="▶")
        self._right_nav.add_css_class("quick-nav")
        if on_next_group:
            self._right_nav.connect("clicked", lambda _: on_next_group())
        nav_row.append(self._right_nav)

    def update(self, station_ids: list[str], station_names: list[str] | None = None):
        self._station_ids = station_ids
        for i, btn in enumerate(self._btns):
            has = i < len(station_ids)
            btn.set_sensitive(has)
            if has and station_names and i < len(station_names):
                btn.set_tooltip_text(station_names[i])
            else:
                btn.set_tooltip_text(None)

    def set_active_group(self, group: str | None):
        self._group_label.set_label(group or "ALL")

    def update_nav_tooltips(self, prev_group: str | None, next_group: str | None):
        self._left_nav.set_tooltip_text(f"Prev: {prev_group or 'ALL'}")
        self._right_nav.set_tooltip_text(f"Next: {next_group or 'ALL'}")

    def _on_click(self, _, idx: int):
        if idx < len(self._station_ids):
            self._on_select(self._station_ids[idx])


# ── Group/page selector bar ────────────────────────────────────────────────────
class GroupBar(Gtk.Box):
    """Horizontal strip of page-tab buttons: ALL | FM1 | FM2 | AM1 | INT1 | …"""
    def __init__(self, on_group_changed):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        self.add_css_class("group-bar")
        self._on_group_changed = on_group_changed
        self._active: str | None = None
        self._btns: dict[str, Gtk.Button] = {}

    def load(self, groups: list[str]):
        child = self.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self.remove(child)
            child = nxt
        self._btns.clear()
        all_items = ["ALL"] + sorted(set(groups))
        for g in all_items:
            btn = Gtk.Button(label=g)
            btn.add_css_class("group-tab")
            btn.connect("clicked", self._on_click, g)
            self.append(btn)
            self._btns[g] = btn
        self._highlight(self._active)
        # Hide bar if there's only one real group (no point showing it)
        self.set_visible(len(set(groups)) > 1)

    def set_active(self, group: str | None):
        self._active = group
        self._highlight(group)

    def _highlight(self, group: str | None):
        key = group or "ALL"
        for name, btn in self._btns.items():
            if name == key:
                btn.add_css_class("active")
            else:
                btn.remove_css_class("active")

    def _on_click(self, _, group: str):
        g = None if group == "ALL" else group
        self._active = g
        self._highlight(g)
        self._on_group_changed(g)

    def get_active(self) -> str | None:
        return self._active

    def get_adjacent(self) -> tuple[str | None, str | None]:
        """Return (prev_group, next_group) labels for nav tooltips."""
        keys = list(self._btns.keys())
        if len(keys) <= 1:
            return None, None
        current_key = self._active or "ALL"
        idx = keys.index(current_key) if current_key in keys else 0
        prev_key = keys[(idx - 1) % len(keys)]
        next_key = keys[(idx + 1) % len(keys)]
        return (None if prev_key == "ALL" else prev_key), (None if next_key == "ALL" else next_key)

    def navigate(self, delta: int):
        """Cycle active group by delta steps (±1). No-op if ≤1 group."""
        keys = list(self._btns.keys())
        if len(keys) <= 1:
            return
        current_key = (self._active or "ALL")
        idx = keys.index(current_key) if current_key in keys else 0
        self._on_click(None, keys[(idx + delta) % len(keys)])


# ── Station row (name button + ✎ / ✕ actions) ─────────────────────────────────
class StationRowWidget(Gtk.Box):
    def __init__(self, station: dict, on_select, on_edit, on_delete, on_freq_change, on_group_change):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        self._station = station
        self._on_delete = on_delete
        self._on_freq_change = on_freq_change
        self._on_group_change = on_group_change
        self._confirm_timer: int | None = None

        name_btn = Gtk.Button(label=station["name"])
        name_btn.add_css_class("station-row")
        name_btn.set_hexpand(True)
        name_btn.set_halign(Gtk.Align.FILL)
        label = name_btn.get_child()
        if label:
            label.set_ellipsize(Pango.EllipsizeMode.END)
        name_btn.connect("clicked", lambda _: on_select(station["id"]))
        self.append(name_btn)
        self._name_btn = name_btn

        freq = station.get("frequency")
        if freq:
            freq_btn = Gtk.Button(label=freq)
            freq_btn.add_css_class("freq-badge")
            freq_btn.set_valign(Gtk.Align.CENTER)
            freq_btn.set_tooltip_text("Click to change frequency")
            freq_btn.connect("clicked", self._show_freq_popover)
            self.append(freq_btn)
            self._freq_btn = freq_btn
        else:
            self._freq_btn = None

        self._group = station.get("group", "INT1")
        group_btn = Gtk.Button(label=self._group)
        group_btn.add_css_class("group-badge")
        group_btn.set_valign(Gtk.Align.CENTER)
        group_btn.set_tooltip_text("Click to change page")
        group_btn.connect("clicked", self._show_group_popover)
        self.append(group_btn)
        self._group_btn = group_btn

        edit_btn = Gtk.Button(label="✎")
        edit_btn.add_css_class("row-action")
        edit_btn.set_tooltip_text("Edit station")
        edit_btn.connect("clicked", lambda _: on_edit(station))
        self.append(edit_btn)

        self._del_btn = Gtk.Button(label="✕")
        self._del_btn.add_css_class("row-action")
        self._del_btn.set_tooltip_text("Remove station")
        self._del_btn.connect("clicked", self._on_del_click)
        self.append(self._del_btn)

    def _show_freq_popover(self, btn: Gtk.Button):
        popover = Gtk.Popover()
        popover.set_parent(btn)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        box.set_margin_top(4)
        box.set_margin_bottom(4)
        box.set_margin_start(4)
        box.set_margin_end(4)
        for freq in _PHILLY_FREQ_POOL:
            row_btn = Gtk.Button(label=freq)
            row_btn.add_css_class("freq-pick")
            def _pick(_, f=freq):
                popover.popdown()
                self._on_freq_change(self._station["id"], f)
            row_btn.connect("clicked", _pick)
            box.append(row_btn)
        popover.set_child(box)
        popover.popup()

    def _show_group_popover(self, btn: Gtk.Button):
        popover = Gtk.Popover()
        popover.set_parent(btn)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        box.set_margin_top(4)
        box.set_margin_bottom(4)
        box.set_margin_start(4)
        box.set_margin_end(4)
        for g in ["FM1", "FM2", "FM3", "FM4", "AM1", "AM2", "INT1", "INT2"]:
            row_btn = Gtk.Button(label=g)
            row_btn.add_css_class("group-pick")
            def _pick(_, grp=g):
                popover.popdown()
                self._on_group_change(self._station["id"], grp)
            row_btn.connect("clicked", _pick)
            box.append(row_btn)
        sep = Gtk.Separator()
        sep.set_margin_top(3)
        sep.set_margin_bottom(3)
        box.append(sep)
        entry = Gtk.Entry()
        entry.set_placeholder_text("custom…")
        def _on_entry_activate(_e):
            name = entry.get_text().strip()
            if name:
                popover.popdown()
                self._on_group_change(self._station["id"], name)
        entry.connect("activate", _on_entry_activate)
        box.append(entry)
        popover.set_child(box)
        popover.popup()

    def group(self) -> str:
        return self._group

    def _on_del_click(self, *_):
        # Two-click confirm: first click → "sure?" state for 2.5 s
        if "confirm" in self._del_btn.get_css_classes():
            self._clear_confirm_timer()
            self._del_btn.remove_css_class("confirm")
            self._del_btn.set_label("✕")
            self._on_delete(self._station["id"])
        else:
            self._del_btn.add_css_class("confirm")
            self._del_btn.set_label("?")
            self._confirm_timer = GLib.timeout_add(2500, self._revert_confirm)

    def _revert_confirm(self):
        self._del_btn.remove_css_class("confirm")
        self._del_btn.set_label("✕")
        self._confirm_timer = None
        return False

    def _clear_confirm_timer(self):
        if self._confirm_timer is not None:
            GLib.source_remove(self._confirm_timer)
            self._confirm_timer = None

    def set_active(self, active: bool):
        if active:
            self._name_btn.add_css_class("active")
        else:
            self._name_btn.remove_css_class("active")

    def matches(self, text: str) -> bool:
        return text.lower() in self._station["name"].lower()

    def station_id(self) -> str:
        return self._station["id"]


# ── Station List widget ───────────────────────────────────────────────────────
class StationList(Gtk.Box):
    def __init__(self, on_select, on_edit, on_delete, on_freq_change, on_group_change):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add_css_class("station-list")
        self._on_select       = on_select
        self._on_edit         = on_edit
        self._on_delete       = on_delete
        self._on_freq_change  = on_freq_change
        self._on_group_change = on_group_change
        self._rows: list[StationRowWidget] = []
        self._active_id: str | None = None
        self._filter_text = ""
        self._active_group: str | None = None

    def _clear(self):
        child = self.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self.remove(child)
            child = nxt
        self._rows.clear()

    def load(self, stations: list[dict]):
        self._clear()
        for s in stations:
            row = StationRowWidget(s, self._on_select, self._on_edit, self._on_delete, self._on_freq_change, self._on_group_change)
            self.append(row)
            self._rows.append(row)
        self._apply_filter()
        self.set_active(self._active_id)

    def apply_filter(self, text: str):
        self._filter_text = text
        self._apply_filter()

    def apply_group(self, group: str | None):
        self._active_group = group
        self._apply_filter()

    def _apply_filter(self):
        for row in self._rows:
            visible = row.matches(self._filter_text) if self._filter_text else True
            if visible and self._active_group:
                visible = row.group() == self._active_group
            row.set_visible(visible)

    def set_active(self, sid: str | None):
        self._active_id = sid
        for row in self._rows:
            row.set_active(row.station_id() == sid)

    def visible_station_ids(self) -> list[str]:
        return [row.station_id() for row in self._rows if row.get_visible()]

    def visible_stations(self) -> list[dict]:
        return [row._station for row in self._rows if row.get_visible()]


# ── Inline edit / add form ────────────────────────────────────────────────────
class InlineForm(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.add_css_class("inline-form")
        self.set_visible(False)

        self._title = Gtk.Label(label="")
        self._title.add_css_class("form-title")
        self._title.set_halign(Gtk.Align.START)
        self.append(self._title)

        for field_name, attr, placeholder in [
            ("name", "_name_entry", "Station name"),
            ("url",  "_url_entry",  "https://stream.example.com/mp3"),
        ]:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            lbl = Gtk.Label(label=field_name)
            lbl.add_css_class("inline-form")
            lbl.set_xalign(1.0)
            lbl.set_size_request(30, -1)
            row.append(lbl)
            entry = Gtk.Entry()
            entry.set_hexpand(True)
            entry.set_placeholder_text(placeholder)
            row.append(entry)
            setattr(self, attr, entry)
            setattr(self, f"_{field_name}_row", row)
            self.append(row)

        self._error = Gtk.Label(label="")
        self._error.add_css_class("form-error")
        self._error.set_halign(Gtk.Align.START)
        self._error.set_visible(False)
        self.append(self._error)

        btns = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        btns.set_halign(Gtk.Align.END)
        self._cancel_btn = Gtk.Button(label="cancel")
        self._cancel_btn.add_css_class("cancel")
        self._save_btn = Gtk.Button(label="save")
        btns.append(self._cancel_btn)
        btns.append(self._save_btn)
        self.append(btns)

        self._station_id: str | None = None
        self._on_save = None
        self._on_cancel = None

        self._cancel_btn.connect("clicked", lambda _: self._do_cancel())
        self._save_btn.connect("clicked",   lambda _: self._do_save())
        self._name_entry.connect("activate", lambda _: self._url_entry.grab_focus() if self._url_row.get_visible() else self._do_save())
        self._url_entry.connect("activate",  lambda _: self._do_save())

    def show_add(self, on_save, on_cancel):
        self._station_id = None
        self._on_save = on_save
        self._on_cancel = on_cancel
        self._title.set_label("+ Add Station")
        self._name_entry.set_text("")
        self._url_entry.set_text("")
        self._url_row.set_visible(True)
        self._error.set_visible(False)
        self.set_visible(True)
        self._name_entry.grab_focus()

    def show_edit(self, station: dict, on_save, on_cancel):
        self._station_id = station["id"]
        self._on_save = on_save
        self._on_cancel = on_cancel
        self._title.set_label(f"✎ rename")
        self._name_entry.set_text(station.get("name", ""))
        self._url_row.set_visible(False)
        self._error.set_visible(False)
        self.set_visible(True)
        self._name_entry.grab_focus()

    def show_error(self, msg: str):
        self._error.set_label(msg)
        self._error.set_visible(True)

    def _do_save(self):
        name = self._name_entry.get_text().strip()
        url  = self._url_entry.get_text().strip()
        if self._on_save:
            self._on_save(self._station_id, name, url)

    def _do_cancel(self):
        self.set_visible(False)
        if self._on_cancel:
            self._on_cancel()


# ── Discover panel (RadioBrowser search) ──────────────────────────────────────
class DiscoverPanel(Gtk.Box):
    def __init__(self, on_add_number, on_back):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.add_css_class("discover-panel")

        # Header: [← lib]  [search entry ...............]
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        back_btn = Gtk.Button(label="← lib")
        back_btn.add_css_class("back-btn")
        back_btn.connect("clicked", lambda _: on_back())
        header.append(back_btn)

        self._entry = Gtk.Entry()
        self._entry.set_placeholder_text("search stations…")
        self._entry.set_hexpand(True)
        self._entry.add_css_class("discover-entry")
        self._entry.connect("activate", self._on_activate)
        header.append(self._entry)

        self.append(header)

        self._status = Gtk.Label(label="type a query and press Enter")
        self._status.add_css_class("discover-status")
        self._status.set_halign(Gtk.Align.START)
        self.append(self._status)

        self._results_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.append(self._results_box)

        self._on_add_number = on_add_number
        self._current_results: list[dict] = []

    def grab_search_focus(self):
        self._entry.grab_focus()

    def _on_activate(self, *_):
        query = self._entry.get_text().strip()
        if not query:
            return
        self._clear_results()
        self._status.set_label(f"searching '{query}'…")
        self._status.set_visible(True)
        threading.Thread(target=self._bg_search, args=(query,), daemon=True).start()

    def _bg_search(self, query: str):
        results = run_search(query)
        GLib.idle_add(self._show_results, results)

    def _clear_results(self):
        child = self._results_box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self._results_box.remove(child)
            child = nxt
        self._current_results = []

    def _show_results(self, results: list[dict]):
        self._clear_results()
        self._current_results = results
        if not results:
            self._status.set_label("no results")
            self._status.set_visible(True)
            return False
        self._status.set_visible(False)
        for r in results:
            self._results_box.append(self._make_row(r))
        return False

    def _make_row(self, r: dict) -> Gtk.Box:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        row.add_css_class("discover-result")

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        info.set_hexpand(True)

        name_lbl = Gtk.Label(label=r.get("name", "?"))
        name_lbl.add_css_class("discover-name")
        name_lbl.set_halign(Gtk.Align.START)
        name_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        info.append(name_lbl)

        meta = f"{r.get('country', '-')} | {r.get('codec', '-')} {r.get('bitrate', '-')}kbps"
        meta_lbl = Gtk.Label(label=meta)
        meta_lbl.add_css_class("discover-meta")
        meta_lbl.set_halign(Gtk.Align.START)
        meta_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        info.append(meta_lbl)

        row.append(info)

        idx = r["index"]
        add_btn = Gtk.Button(label=f"+{idx}")
        add_btn.add_css_class("discover-add")
        add_btn.connect("clicked", lambda _, n=idx, b=add_btn: self._do_add(n, b))
        row.append(add_btn)

        return row

    def _do_add(self, number: int, btn: Gtk.Button):
        btn.set_sensitive(False)
        btn.set_label("…")
        threading.Thread(target=self._bg_add, args=(number, btn), daemon=True).start()

    def _bg_add(self, number: int, btn: Gtk.Button):
        err = run_add_from_search(number)
        GLib.idle_add(self._finish_add, err, btn, number)

    def _finish_add(self, err: str | None, btn: Gtk.Button, number: int):
        if err:
            btn.set_label(f"+{number}")
            btn.set_sensitive(True)
        else:
            btn.add_css_class("added")
            btn.set_label("✓")
            self._on_add_number()
        return False


# ── Main window ───────────────────────────────────────────────────────────────
class SqlchPopupWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_default_size(POPUP_WIDTH, -1)

        Gtk4LayerShell.init_for_window(self)
        Gtk4LayerShell.set_layer(self, Gtk4LayerShell.Layer.TOP)
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.TOP,   True)
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.RIGHT,  True)
        Gtk4LayerShell.set_margin(self, Gtk4LayerShell.Edge.TOP,   40)
        Gtk4LayerShell.set_margin(self, Gtk4LayerShell.Edge.RIGHT,  6)
        # ON_DEMAND: grab keyboard when a text entry is focused
        Gtk4LayerShell.set_keyboard_mode(self, Gtk4LayerShell.KeyboardMode.ON_DEMAND)

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.add_css_class("popup")
        self.set_child(outer)

        badge = Gtk.Label(label="SQLCH  ◈  DEH-S")
        badge.add_css_class("mfr-badge")
        badge.set_halign(Gtk.Align.END)
        outer.append(badge)

        # ── Now Playing ──────────────────────────────────────────────────────
        self._collapsed = False
        self._bt_active: bool = False
        self._group_bar_natural_visible = False
        self._now_playing = NowPlaying(
            on_collapse=self._toggle_collapse,
            on_station_select=self._on_station_select,
            on_prev_group=lambda: self._group_bar.navigate(-1),
            on_next_group=lambda: self._group_bar.navigate(1),
        )
        outer.append(self._now_playing)

        self._div = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        seam_hi = Gtk.Separator()
        seam_hi.add_css_class("seam")
        seam_sh = Gtk.Separator()
        seam_sh.add_css_class("seam-shadow")
        self._div.append(seam_hi)
        self._div.append(seam_sh)
        outer.append(self._div)

        # ── Toolbar: [filter entry] [🌐 discover] [+ add] ───────────────────
        self._toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        toolbar = self._toolbar
        toolbar.add_css_class("toolbar")

        self._filter_entry = Gtk.Entry()
        self._filter_entry.set_placeholder_text("filter…")
        self._filter_entry.set_hexpand(True)
        self._filter_entry.connect("changed", self._on_filter_changed)
        toolbar.append(self._filter_entry)

        self._discover_btn = Gtk.Button(label="🌐")
        self._discover_btn.set_tooltip_text("Search RadioBrowser")
        self._discover_btn.connect("clicked", self._on_discover_clicked)
        toolbar.append(self._discover_btn)

        add_btn = Gtk.Button(label="+")
        add_btn.set_tooltip_text("Add station by URL")
        add_btn.connect("clicked", self._on_add_clicked)
        toolbar.append(add_btn)

        outer.append(toolbar)

        self._seam2_hi = Gtk.Separator()
        self._seam2_hi.add_css_class("seam")
        self._seam2_sh = Gtk.Separator()
        self._seam2_sh.add_css_class("seam-shadow")
        outer.append(self._seam2_hi)
        outer.append(self._seam2_sh)

        # ── Group/page selector bar ───────────────────────────────────────────
        self._group_bar = GroupBar(on_group_changed=self._on_group_tab_changed)
        outer.append(self._group_bar)

        # ── Inline form (hidden until edit/add triggered) ────────────────────
        self._form = InlineForm()
        outer.append(self._form)

        # ── Scrollable body: stack between library list and discover panel ───
        self._scroll = Gtk.ScrolledWindow()
        scroll = self._scroll
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_max_content_height(300)
        scroll.set_propagate_natural_height(True)
        outer.append(scroll)

        self._stack = Gtk.Stack()
        self._stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self._stack.set_transition_duration(150)
        scroll.set_child(self._stack)

        self._station_list = StationList(
            on_select=self._on_station_select,
            on_edit=self._on_station_edit,
            on_delete=self._on_station_delete,
            on_freq_change=self._on_freq_change,
            on_group_change=self._on_group_change,
        )
        self._stack.add_named(self._station_list, "library")

        self._discover = DiscoverPanel(
            on_add_number=self._on_station_added,
            on_back=self._show_library,
        )
        self._stack.add_named(self._discover, "discover")

        self._refresh_stations()
        self._stack.set_visible_child_name("library")

        # ── Start polling ────────────────────────────────────────────────────
        self._poll()
        GLib.timeout_add(POLL_MS, self._poll)
        self._refresh_bt()
        GLib.timeout_add(15_000, self._refresh_bt)

    # ── Collapse toggle ───────────────────────────────────────────────────────
    def _toggle_collapse(self):
        self._collapsed = not self._collapsed
        show = not self._collapsed
        self._div.set_visible(show)
        self._toolbar.set_visible(show)
        self._seam2_hi.set_visible(show)
        self._seam2_sh.set_visible(show)
        self._group_bar.set_visible(show and self._group_bar_natural_visible)
        self._form.set_visible(False)   # always re-hide form on collapse/expand
        self._scroll.set_visible(show)
        self._update_collapsed_bar()
        self._now_playing.set_collapsed(self._collapsed)

    def _update_collapsed_bar(self):
        stations = self._station_list.visible_stations()[:6]
        ids = [s["id"] for s in stations]
        names = [s["name"] for s in stations]
        self._now_playing.update_stations(ids, names)
        active = self._group_bar.get_active()
        prev_group, next_group = self._group_bar.get_adjacent()
        self._now_playing.set_quick_group(active)
        self._now_playing.update_quick_nav_tooltips(prev_group, next_group)

    # ── View switching ────────────────────────────────────────────────────────
    def _show_library(self):
        self._stack.set_visible_child_name("library")
        self._discover_btn.remove_css_class("active")

    def _show_discover(self):
        self._stack.set_visible_child_name("discover")
        self._discover_btn.add_css_class("active")
        self._discover.grab_search_focus()

    # ── Toolbar handlers ──────────────────────────────────────────────────────
    def _on_filter_changed(self, entry):
        self._station_list.apply_filter(entry.get_text())

    def _on_discover_clicked(self, *_):
        if self._stack.get_visible_child_name() == "discover":
            self._show_library()
        else:
            self._form.set_visible(False)
            self._show_discover()

    def _on_add_clicked(self, *_):
        self._show_library()
        self._form.show_add(
            on_save=self._on_form_save,
            on_cancel=lambda: None,
        )

    # ── Station actions ───────────────────────────────────────────────────────
    def _on_station_select(self, station_id: str):
        daemon_send({"cmd": "play", "query": station_id})

    def _on_station_edit(self, station: dict):
        self._show_library()
        self._form.show_edit(
            station=station,
            on_save=self._on_form_save,
            on_cancel=lambda: None,
        )

    def _refresh_stations(self):
        stations = get_station_list()
        self._station_list.load(stations)
        groups = [s["group"] for s in stations]
        self._group_bar.load(groups)
        self._group_bar_natural_visible = len(set(groups)) > 1
        if not self._collapsed:
            self._group_bar.set_visible(self._group_bar_natural_visible)
        self._update_collapsed_bar()

    def _on_station_delete(self, station_id: str):
        err = library_remove(station_id)
        if not err:
            self._refresh_stations()

    def _on_freq_change(self, station_id: str, freq: str):
        err = library_set_frequency(station_id, freq)
        if not err:
            self._refresh_stations()

    def _on_group_tab_changed(self, group: str | None):
        self._station_list.apply_group(group)
        self._now_playing.set_quick_group(group)
        self._update_collapsed_bar()

    def _on_group_change(self, station_id: str, group: str):
        err = library_set_group(station_id, group)
        if not err:
            self._refresh_stations()

    def _on_station_added(self):
        """Called after a RadioBrowser add succeeds — refresh library list."""
        self._refresh_stations()

    def _on_form_save(self, station_id: str | None, name: str, url: str):
        if station_id is None:
            err = library_add_url(name, url)
        else:
            err = library_update(station_id, name, url)

        if err:
            self._form.show_error(err)
        else:
            self._form.set_visible(False)
            self._refresh_stations()

    # ── Polling ───────────────────────────────────────────────────────────────
    def _poll(self) -> bool:
        threading.Thread(target=self._do_poll, daemon=True).start()
        return True

    def _do_poll(self):
        resp       = daemon_send({"cmd": "status"})
        icy        = get_icy_track()
        vol, muted = _get_vol_state()
        bitrate    = _get_stream_bitrate()
        channels   = _get_stream_channels()
        GLib.idle_add(self._apply_poll, resp, icy, vol, muted, bitrate, channels)

    def _apply_poll(self, resp, icy, vol, muted, bitrate, channels):
        self._now_playing.update(resp, icy=icy)
        playing = bool(resp and resp.get("ok") and resp.get("current"))
        self._now_playing.update_indicators(bitrate, vol, muted, self._bt_active, playing, channels)
        self._station_list.set_active(self._now_playing.get_current_id())
        return False

    def _refresh_bt(self) -> bool:
        threading.Thread(target=self._do_bt_check, daemon=True).start()
        return True

    def _do_bt_check(self):
        active = _get_bt_active()
        GLib.idle_add(self._apply_bt, active)

    def _apply_bt(self, active: bool):
        self._bt_active = active
        return False


class SqlchPopupApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="dev.prepko.sqlch-popup")

    def do_activate(self):
        win = SqlchPopupWindow(self)
        win.present()


def _backfill_frequencies():
    """Assign frequencies to any library stations that lack one (runs on every startup)."""
    lib = _load_library()
    changed = False
    for station in lib["stations"]:
        if station.get("frequency") is None:
            freq = _assign_frequency(station["id"])
            if freq is not None:       # only write when pool had something to give
                station["frequency"] = freq
                changed = True
    if changed:
        _save_library(lib)


if __name__ == "__main__":
    _backfill_frequencies()
    SqlchPopupApp().run()
