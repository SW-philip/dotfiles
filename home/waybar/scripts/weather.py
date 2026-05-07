#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Waybar Weather script — bemenu edition

Features
--------
* Reads a colour palette from ~/.config/waybar/palette.sh
* Caches state (default / forecast) in $XDG_CACHE_HOME
* Location managed via ~/.config/waybar/weather_location.json
* All UI via bemenu (100% Wayland native, no zenity/GTK dialogs)
* Auto-detect disabled — VPN makes IP geolocation useless.
  If no saved location is set, prompts immediately to add one.
* Right-click to switch or add locations.
"""

import json
import os
import pathlib
import random
import re
import subprocess
import sys
import unicodedata
from collections import defaultdict
from datetime import date as date_type, datetime, timezone
from typing import Dict, List, Optional, Tuple

import requests

# ──────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────
HOME       = pathlib.Path.home()
CACHE_DIR  = HOME / ".cache"
CACHE_DIR.mkdir(parents=True, exist_ok=True)

STATE_FILE = CACHE_DIR / "weather_state"
if not STATE_FILE.exists():
    STATE_FILE.write_text("default")
STATE = STATE_FILE.read_text().strip()   # "default" | "forecast"

PALETTE_FILE    = HOME / ".config/waybar/palette.sh"
LOCATION_CONFIG = HOME / ".config/waybar/weather_location.json"
SNARK_FILE      = HOME / ".config/waybar/snark.json"

UNITS   = "imperial"
API_KEY = os.environ.get("OPENWEATHERMAP_API_KEY", "")

# ──────────────────────────────────────────────────────────────────────
# Palette
# ──────────────────────────────────────────────────────────────────────
def load_palette(path: pathlib.Path) -> Dict[str, str]:
    palette: Dict[str, str] = {}
    try:
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip()
            # Strip bash 'export ' prefix
            if k.startswith("export "):
                k = k[len("export "):].strip()
            # Extract value: grab the quoted content if present, else strip trailing comments
            v_raw = v.strip()
            m = re.match(r'^["\']([^"\']*)["\']', v_raw)
            if m:
                v_clean = m.group(1)
            else:
                v_clean = re.sub(r'\s+#.*$', '', v_raw).strip()
            palette[k] = v_clean
        for _ in range(3):
            for k, v in palette.items():
                palette[k] = re.sub(
                    r"\$(\w+)",
                    lambda m: palette.get(m.group(1), m.group(0)),
                    v,
                )
        # Replace any still-unresolved $VAR references with a safe fallback color
        # so they never produce invalid pango markup
        ink_fallback = palette.get("INK") or palette.get("TEXT_PRIMARY") or palette.get("TEXT") or "#e0def4"
        ink_fallback = re.sub(r"\$\w+", "#e0def4", ink_fallback)
        for k in list(palette.keys()):
            if "$" in palette[k]:
                palette[k] = re.sub(r"\$\w+", ink_fallback, palette[k])
    except Exception:
        pass
    return palette

PALETTE = load_palette(PALETTE_FILE)
INK     = PALETTE.get("INK", "#e0def4")

def condition_color(family: str) -> str:
    """Rosé Pine Moon color representing the weather condition (for bar text)."""
    return {
        "sun":   "#f6c177",  # GOLD    — sunny
        "cloud": "#908caa",  # SUBTLE  — overcast/grey
        "fog":   "#6e6a86",  # MUTED   — foggy
        "rain":  "#9ccfd8",  # FOAM    — rainy blue
        "snow":  "#e0def4",  # TEXT    — near-white snow
        "storm": "#eb6f92",  # LOVE    — severe/alert red
    }.get(family, "#c4c0d8")  # MUTED_ICON fallback

def temp_color(t: float) -> str:
    """Rosé Pine Moon heat-scale for °F temperatures."""
    if t < 20:  return "#9ccfd8"  # FOAM      — icy
    if t < 40:  return "#7ab3c0"  # tint foam — cold
    if t < 55:  return "#908caa"  # SUBTLE    — cool
    if t < 70:  return "#e0def4"  # TEXT      — comfortable
    if t < 85:  return "#f6c177"  # GOLD      — warm
    if t < 95:  return "#f0a020"  # WARNING   — hot
    return "#eb6f92"               # LOVE      — scorching

# ──────────────────────────────────────────────────────────────────────
# Snark
# ──────────────────────────────────────────────────────────────────────
def load_snark() -> dict:
    try:
        return json.loads(SNARK_FILE.read_text())
    except Exception:
        return {}

def pick_weather_snark(family: str) -> str:
    data = load_snark()
    options = data.get("weather", {}).get(family, [])
    return random.choice(options) if options else ""

# ──────────────────────────────────────────────────────────────────────
# Weather families & glyphs
# ──────────────────────────────────────────────────────────────────────
WEATHER_FAMILY = {
    "clear": "sun", "clouds": "cloud",
    "rain": "rain", "drizzle": "rain",
    "snow": "snow", "thunderstorm": "storm",
    "mist": "fog", "fog": "fog", "haze": "fog",
    "smoke": "fog", "dust": "fog", "sand": "fog",
}

GLYPHS = {
    "sun":     {"light": "󰖙", "medium": "󰖙", "heavy": "󰖙"},
    "rain":    {"light": "󰖖", "medium": "󰖗", "heavy": "󰖘"},
    "snow":    {"light": "󰖘", "heavy": "󰼶"},
    "cloud":   {"light": "󰖐", "medium": "󰖑", "heavy": "󰖝"},
    "fog":     {"light": "󰖑", "heavy": "󰖝"},
    "storm":   {"heavy": "󰖓"},
    "unknown": {"medium": "󰔟"},
}

# ──────────────────────────────────────────────────────────────────────
# Intensity helpers
# ──────────────────────────────────────────────────────────────────────
def cloud_intensity(w):
    c = w.get("clouds", {}).get("all", 0)
    return "light" if c < 25 else "medium" if c < 70 else "heavy"

def rain_intensity(w):
    r = w.get("rain", {}).get("1h", 0)
    return "light" if r < 1 else "medium" if r < 5 else "heavy"

def snow_intensity(w):
    return "heavy" if w.get("snow", {}).get("1h", 0) > 1 else "light"

def visibility_intensity(w):
    v = w.get("visibility", 10_000)
    return "light" if v > 6000 else "medium" if v > 2000 else "heavy"

# ──────────────────────────────────────────────────────────────────────
# Misc helpers
# ──────────────────────────────────────────────────────────────────────
def glyph_color(family, intensity):
    return PALETTE.get(f"WX_{family.upper()}_{intensity.upper()}", INK)

def sanitize(text):
    return re.sub(r"[\x00-\x09\x0B-\x1F\x7F]", "", unicodedata.normalize("NFC", text))

def wrap_json(text, tooltip, cls):
    return json.dumps({"text": text, "tooltip": tooltip, "class": cls}, ensure_ascii=False)

# ──────────────────────────────────────────────────────────────────────
# Location config
# ──────────────────────────────────────────────────────────────────────
def load_location_config() -> dict:
    if LOCATION_CONFIG.exists():
        try:
            return json.loads(LOCATION_CONFIG.read_text())
        except Exception:
            pass
    return {"USE_LOCATION": None, "SAVED_LOCATIONS": []}

def save_location_config(cfg: dict) -> None:
    LOCATION_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    LOCATION_CONFIG.write_text(json.dumps(cfg, indent=2))

def resolve_location(cfg: dict) -> Tuple[Optional[float], Optional[float], str]:
    use = cfg.get("USE_LOCATION")
    if use:
        match = next((l for l in cfg["SAVED_LOCATIONS"] if l["name"] == use), None)
        if match:
            return match["lat"], match["lon"], match["name"]
    return None, None, "None"

# ──────────────────────────────────────────────────────────────────────
# bemenu helpers
# ──────────────────────────────────────────────────────────────────────
BEMENU_OPTS = [

    "-n",                          # no overlap with waybar
    "-W", "0.25",                  # narrow column, not full width
    "-M", "10",                    # small margin from edge
    "-H", "28",                    # line height matching your waybar height (45px bar, so ~28 looks right)
    "-i",                          # case insensitive
    "-l", "10",                    # max lines
    "-p", "",                      # placeholder set per call
    "--fn", "JetBrains Mono 12",
    "--tb", "#1f1d2e",             # title background (Rosé Pine base)
    "--tf", "#e0def4",             # title foreground
    "--fb", "#1f1d2e",             # filter background
    "--ff", "#e0def4",             # filter foreground
    "--nb", "#1f1d2e",             # normal background
    "--nf", "#908caa",             # normal foreground (subtle)
    "--hb", "#26233a",             # highlight background (surface)
    "--hf", "#ebbcba",             # highlight foreground (rose)
    "--sb", "#26233a",             # selected background
    "--sf", "#ebbcba",             # selected foreground
    "--ab", "#1f1d2e",
    "--af", "#908caa",
    "--bdr", "#403d52",            # border (overlay)
    "-B", "2",
    "--border-radius", "7",
]

def _wayland_env() -> dict:
    """Ensure WAYLAND_DISPLAY, XDG_RUNTIME_DIR, and BEMENU_BACKEND are set."""
    env = os.environ.copy()
    env["BEMENU_BACKEND"] = "wayland"
    runtime = env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    env.setdefault("XDG_RUNTIME_DIR", runtime)
    if not env.get("WAYLAND_DISPLAY"):
        try:
            sockets = sorted(
                f for f in os.listdir(runtime)
                if f.startswith("wayland-") and not f.endswith(".lock")
            )
            if sockets:
                env["WAYLAND_DISPLAY"] = sockets[0]
        except Exception:
            pass
    return env

def bemenu_select(prompt: str, options: List[str]) -> Optional[str]:
    """Show a bemenu list. Returns chosen string or None."""
    opts = BEMENU_OPTS.copy()
    opts[opts.index("") ] = prompt   # replace placeholder with real prompt
    result = subprocess.run(
        ["bemenu", *opts],
        input="\n".join(options),
        capture_output=True,
        text=True,
        env=_wayland_env(),
    )
    chosen = result.stdout.strip()
    return chosen if chosen else None

def bemenu_input(prompt: str) -> Optional[str]:
    """Free-text input via bemenu (empty list, just type)."""
    opts = BEMENU_OPTS.copy()
    opts[opts.index("")] = prompt
    result = subprocess.run(
        ["bemenu", *opts],
        input="",
        capture_output=True,
        text=True,
        env=_wayland_env(),
    )
    value = result.stdout.strip()
    return value if value else None

def bemenu_confirm(prompt: str) -> bool:
    """Yes/No via bemenu."""
    chosen = bemenu_select(prompt, ["Yes", "No"])
    return chosen == "Yes"

# ──────────────────────────────────────────────────────────────────────
# Right-click location menu
# ──────────────────────────────────────────────────────────────────────
ADD_NEW = "+ Add new location"

def handle_right_click(cfg: dict) -> None:
    saved_names = [l["name"] for l in cfg["SAVED_LOCATIONS"]]
    options = saved_names + [ADD_NEW]

    chosen = bemenu_select("Select location:", options)
    if not chosen:
        return

    if chosen == ADD_NEW:
        add_location(cfg)
        return

    cfg["USE_LOCATION"] = chosen
    save_location_config(cfg)

def add_location(cfg: dict) -> None:
    name = bemenu_input("Location name:")
    if not name:
        return

    lat_str = bemenu_input("Latitude (e.g. 40.7128):")
    try:
        lat = float(lat_str)
    except (TypeError, ValueError):
        return

    lon_str = bemenu_input("Longitude (e.g. -74.0060):")
    try:
        lon = float(lon_str)
    except (TypeError, ValueError):
        return

    new_loc = {"name": name, "lat": lat, "lon": lon}

    if bemenu_confirm(f"Save '{name}' to locations?"):
        cfg["SAVED_LOCATIONS"].append(new_loc)
        cfg["USE_LOCATION"] = name

    save_location_config(cfg)

# ──────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────
def main() -> None:
    global STATE
    if "--mode" in sys.argv:
        idx = sys.argv.index("--mode")
        if idx + 1 < len(sys.argv):
            STATE = sys.argv[idx + 1]

    cfg = load_location_config()

    if os.environ.get("BUTTON") == "3":
        handle_right_click(cfg)
        sys.exit(0)

    lat, lon, city = resolve_location(cfg)

    # No location saved — prompt immediately instead of guessing via IP
    if lat is None:
        print(wrap_json("󰔟 No location", "Right-click to add a location", "weather error"))
        sys.exit(0)

    # Fetch current weather
    try:
        weather_resp = requests.get(
            "https://api.openweathermap.org/data/2.5/weather",
            params={"lat": lat, "lon": lon, "appid": API_KEY, "units": UNITS},
            timeout=6,
        ).json()
    except Exception:
        print(wrap_json("󰔟", "Weather API unreachable", "weather error"))
        sys.exit(0)

    if "main" not in weather_resp:
        msg = weather_resp.get("message", "Unknown error")
        print(wrap_json("󰔟", f"Weather API error: {msg}", "weather error"))
        sys.exit(0)

    # ── Rosé Pine semantic color ladder (loaded from palette.sh) ──────────
    RP_MUTED  = PALETTE.get("SUBTLE", PALETTE.get("MUTED",  "#908caa"))   # label text
    RP_SUBTLE = PALETTE.get("SUBTLE", "#908caa")   # secondary / description
    RP_TEXT   = PALETTE.get("TEXT",   "#e0def4")   # primary values
    RP_FOAM   = PALETTE.get("FOAM",   "#9ccfd8")   # sky / time accent
    RP_IRIS   = PALETTE.get("IRIS",   "#c4a7e7")   # personality / snark
    RP_GOLD   = PALETTE.get("GOLD",   "#f6c177")   # alert / warm accent
    DIVIDER   = f'<span foreground="{RP_MUTED}">────────────────────</span>'

    # Forecast mode
    if STATE == "forecast":
        try:
            forecast_resp = requests.get(
                "https://api.openweathermap.org/data/2.5/forecast",
                params={"lat": lat, "lon": lon, "appid": API_KEY, "units": UNITS},
                timeout=8,
            ).json()

            # Build a dict: local_date -> list of (local_dt, entry)
            by_day: Dict[str, list] = defaultdict(list)
            for entry in forecast_resp.get("list", []):
                local_dt = datetime.fromtimestamp(entry["dt"], timezone.utc).astimezone()
                day_key = local_dt.strftime("%Y-%m-%d")
                by_day[day_key].append((local_dt, entry))

            TARGET_HOURS = [6, 12, 18]
            HOUR_LABELS  = ["6am", "noon", "6pm"]

            def closest_entry(entries, target_hour):
                return min(entries, key=lambda x: abs(x[0].hour - target_hour))

            FORECAST_EMOJI = {
                "clear": "☀️", "clouds": "☁️", "rain": "🌧️",
                "drizzle": "🌦️", "snow": "❄️", "thunderstorm": "⛈️",
                "mist": "🌫️", "fog": "🌫️", "haze": "🌫️",
            }
            tooltip_lines = []
            bar_days = []
            today = datetime.now().astimezone().date()
            days_collected = 0

            for day_key in sorted(by_day.keys()):
                day_date = date_type.fromisoformat(day_key)
                if day_date <= today:
                    continue
                entries = by_day[day_key]
                label = datetime.strptime(day_key, "%Y-%m-%d").strftime("%A")
                if tooltip_lines:
                    tooltip_lines.append(DIVIDER)
                tooltip_lines.append(f"<b>{label}</b>")
                for target, name in zip(TARGET_HOURS, HOUR_LABELS):
                    local_dt, entry = closest_entry(entries, target)
                    temp = round(entry["main"]["temp"])
                    cond = entry["weather"][0]["main"].lower()
                    emoji = FORECAST_EMOJI.get(cond, "❓")
                    label_col = f"{name:<5}"
                    tooltip_lines.append(f"  <span foreground='{RP_MUTED}'>{label_col}</span>  {emoji}  <span foreground='{temp_color(temp)}'>{temp}°</span>")
                # bar text: just the noon temp with emoji
                noon_dt, noon_entry = closest_entry(entries, 12)
                noon_temp = round(noon_entry["main"]["temp"])
                emoji = {"clear": "☀️", "clouds": "☁️", "rain": "🌧️",
                         "snow": "❄️", "thunderstorm": "⛈️"}.get(
                    noon_entry["weather"][0]["main"].lower(), "❓")
                bar_days.append(f"<span foreground='{RP_TEXT}'>{label}</span> {emoji}<span foreground='{temp_color(noon_temp)}'>{noon_temp}°</span>")
                days_collected += 1
                if days_collected >= 3:
                    break

            if not tooltip_lines:
                print(wrap_json("—", "Forecast unavailable", "weather error"))
                sys.exit(0)

            summary = "  ".join(bar_days)
            tooltip = "\n".join(tooltip_lines)
            print(wrap_json(summary, tooltip, "weather forecast"))
            sys.exit(0)

        except Exception:
            print(wrap_json("❓", "Forecast unavailable", "weather error"))
            sys.exit(0)

    # Current conditions
    temp        = round(weather_resp["main"]["temp"])
    feels       = round(weather_resp["main"]["feels_like"])
    temp_min    = round(weather_resp["main"]["temp_min"])
    temp_max    = round(weather_resp["main"]["temp_max"])
    humidity    = weather_resp["main"]["humidity"]
    pressure    = weather_resp["main"]["pressure"]
    wind        = round(weather_resp["wind"].get("speed", 0))
    gust        = round(weather_resp["wind"].get("gust", 0))
    wind_deg    = weather_resp["wind"].get("deg", 0)
    clouds      = weather_resp.get("clouds", {}).get("all", 0)
    vis_mi      = round(weather_resp.get("visibility", 0) / 1609.34, 1)
    sunrise_ts  = weather_resp["sys"]["sunrise"]
    sunset_ts   = weather_resp["sys"]["sunset"]
    raw_main    = weather_resp["weather"][0]["main"].lower()
    description = weather_resp["weather"][0]["description"]

    compass     = ["N","NE","E","SE","S","SW","W","NW"]
    wind_dir    = compass[round(wind_deg / 45) % 8]
    sunrise_str = datetime.fromtimestamp(sunrise_ts).strftime("%-I:%M %p")
    sunset_str  = datetime.fromtimestamp(sunset_ts).strftime("%-I:%M %p")

    family    = WEATHER_FAMILY.get(raw_main, "unknown")
    intensity = {
        "cloud": cloud_intensity,
        "rain":  rain_intensity,
        "snow":  snow_intensity,
        "fog":   visibility_intensity,
    }.get(family, lambda _: "medium")(weather_resp)

    glyph_set = GLYPHS.get(family, GLYPHS["unknown"])
    glyph     = glyph_set.get(intensity) or next(iter(glyph_set.values()))
    colour    = glyph_color(family, intensity)
    glyph_span = f'<span foreground="{colour}">{glyph}</span>'

    snark = pick_weather_snark(family)
    text  = f"{glyph_span}  <span foreground='{condition_color(family)}'>{temp}°F</span>"

    wind_line = f"<span foreground='{RP_MUTED}'>Wind:</span> <span foreground='{RP_TEXT}'>{wind} mph {wind_dir}</span>"
    if gust > wind:
        wind_line += f"   <span foreground='{RP_MUTED}'>gusts</span> <span foreground='{RP_GOLD}'>{gust} mph</span>"

    tooltip_lines = [
        f"<b>{city}</b>",
        f"<span foreground='{RP_SUBTLE}'>{description.capitalize()}</span>",
        "",
        f"<span foreground='{temp_color(temp)}'>{temp}°F</span>  <span foreground='{RP_MUTED}'>feels</span>  <span foreground='{temp_color(feels)}'>{feels}°F</span>",
        f"<span foreground='{RP_MUTED}'>High</span> <span foreground='{temp_color(temp_max)}'>{temp_max}°</span>   <span foreground='{RP_MUTED}'>Low</span> <span foreground='{temp_color(temp_min)}'>{temp_min}°</span>",
        "",
        f"<span foreground='{RP_MUTED}'>Humidity:</span> <span foreground='{RP_TEXT}'>{humidity}%</span>   <span foreground='{RP_MUTED}'>Pressure:</span> <span foreground='{RP_TEXT}'>{pressure} hPa</span>",
        wind_line,
        f"<span foreground='{RP_MUTED}'>Visibility:</span> <span foreground='{RP_TEXT}'>{vis_mi} mi</span>   <span foreground='{RP_MUTED}'>Clouds:</span> <span foreground='{RP_TEXT}'>{clouds}%</span>",
        "",
        DIVIDER,
        f"<span foreground='{RP_MUTED}'>Sunrise</span> <span foreground='{RP_FOAM}'>{sunrise_str}</span>   <span foreground='{RP_MUTED}'>Sunset</span> <span foreground='{RP_FOAM}'>{sunset_str}</span>",
    ]
    if snark:
        tooltip_lines += ["", f"<span foreground='{RP_IRIS}'>{snark}</span>"]
    tooltip = sanitize("\n".join(tooltip_lines))
    css_class = f"weather {family} {family}-{intensity}"

    print(wrap_json(text, tooltip, css_class))


if __name__ == "__main__":
    main()
