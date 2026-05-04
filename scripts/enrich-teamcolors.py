#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Read teamcolors.json, derive a full 7-color theme palette for each team
using the same ColorMath + readability logic as theme-gen.py, and write
the enriched JSON back.

Usage:
    python3 scripts/enrich-teamcolors.py [--in teamcolors.json] [--out teamcolors-full.json]
"""

import argparse
import json
import sys
import colorsys
from pathlib import Path

# ── Inline ColorMath (mirrors tools/theme-gen.py exactly) ─────────────────────

class ColorMath:
    @staticmethod
    def hex_to_rgb(h: str):
        h = h.lstrip('#')
        return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

    @staticmethod
    def rgb_to_hex(r, g, b) -> str:
        return f"#{int(r):02x}{int(g):02x}{int(b):02x}"

    @staticmethod
    def hex_to_rgb_csv(h: str) -> str:
        r, g, b = ColorMath.hex_to_rgb(h)
        return f"{r},{g},{b}"

    @staticmethod
    def _rgb_to_hsl(r, g, b):
        r_n, g_n, b_n = r/255, g/255, b/255
        mx, mn = max(r_n, g_n, b_n), min(r_n, g_n, b_n)
        l = (mx + mn) / 2
        if mx == mn:
            h = s = 0.0
        else:
            d = mx - mn
            s = d / (2 - mx - mn) if l > 0.5 else d / (mx + mn)
            if mx == r_n:   h = (g_n - b_n) / d + (6 if g_n < b_n else 0)
            elif mx == g_n: h = (b_n - r_n) / d + 2
            else:           h = (r_n - g_n) / d + 4
            h /= 6
        return (h * 360, s, l)

    @staticmethod
    def _hsl_to_rgb(h, s, l):
        h /= 360
        if s == 0:
            v = int(round(l * 255))
            return (v, v, v)
        q = l * (1 + s) if l < 0.5 else l + s - l * s
        p = 2 * l - q
        def _h2r(t):
            if t < 0: t += 1
            if t > 1: t -= 1
            if t < 1/6: return p + (q - p) * 6 * t
            if t < 1/2: return q
            if t < 2/3: return p + (q - p) * (2/3 - t) * 6
            return p
        return tuple(int(round(_h2r(h + o) * 255)) for o in (1/3, 0, -1/3))

    @staticmethod
    def calc_color(hex_c: str, op: str, amount: float) -> str:
        r, g, b = ColorMath.hex_to_rgb(hex_c)
        h, s, l = ColorMath._rgb_to_hsl(r, g, b)
        if op == "lighten":    l = min(1.0, l + amount / 100)
        elif op == "darken":   l = max(0.0, l - amount / 100)
        elif op == "desaturate": s = s * (1 - amount / 100)
        elif op == "saturate": s = s + (1 - s) * amount / 100
        elif op == "shift_hue": h = (h + amount) % 360
        return ColorMath.rgb_to_hex(*ColorMath._hsl_to_rgb(h, s, l))

    @staticmethod
    def _linearize(c: float) -> float:
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    @staticmethod
    def luminance(hex_c: str) -> float:
        r, g, b = ColorMath.hex_to_rgb(hex_c)
        return (0.2126 * ColorMath._linearize(r/255)
              + 0.7152 * ColorMath._linearize(g/255)
              + 0.0722 * ColorMath._linearize(b/255))

    @staticmethod
    def contrast(a: str, b: str) -> float:
        l1, l2 = ColorMath.luminance(a), ColorMath.luminance(b)
        if l1 < l2: l1, l2 = l2, l1
        return (l1 + 0.05) / (l2 + 0.05)

    @staticmethod
    def saturation(hex_c: str) -> float:
        r, g, b = ColorMath.hex_to_rgb(hex_c)
        _, s, _ = ColorMath._rgb_to_hsl(r, g, b)
        return s

    @staticmethod
    def hue(hex_c: str) -> float:
        r, g, b = ColorMath.hex_to_rgb(hex_c)
        h, _, _ = ColorMath._rgb_to_hsl(r, g, b)
        return h

    @staticmethod
    def auto_boost(color: str, bg: str, target: float, direction: str,
                   max_iter: int = 30) -> str:
        cur = color
        for _ in range(max_iter):
            if ColorMath.contrast(cur, bg) >= target:
                return cur
            cur = ColorMath.calc_color(cur, direction, 3)
        return cur


# ── Team-color → theme-palette derivation ─────────────────────────────────────

def _is_real_color(hex_c: str) -> bool:
    """Reject pure black, pure white, and unsaturated greys.
    Dark-but-saturated colors (navy, forest green) are allowed — they'll be
    boosted for contrast later."""
    if not hex_c:
        return False
    sat = ColorMath.saturation(hex_c)
    lum = ColorMath.luminance(hex_c)
    # Allow anything with meaningful saturation; reject only near-white and
    # pure black (luminance < 0.001) — very dark navies are fine.
    return sat > 0.08 and lum < 0.92 and lum > 0.0005


def _is_valid_background(hex_c: str) -> bool:
    """Check if a color is suitable as a theme BASE (dark enough and not pure black/white)."""
    if not hex_c:
        return False
    lum = ColorMath.luminance(hex_c)
    # Accept very dark colors (luminance < 0.15) but reject pure black (#000000)
    # if we want to allow slight variation, OR accept pure black if that's the goal.
    # For Flyers, we want to accept #000000.
    return lum < 0.15

def derive_base(primary: str, secondary: str | None, mode: str = "dark") -> str:
    """
    Determine the BASE color.
    1. If secondary is a valid dark background (e.g., #000000), use it.
    2. Otherwise, crush the primary color into a dark background.
    """
    # Check if secondary is a valid base candidate
    if secondary and _is_valid_background(secondary):
        # If it's pure black, we might want to add a tiny bit of the primary hue
        # to avoid "dead" black, but for Flyers, pure black is likely desired.
        # Let's keep it as-is if it's valid.
        return secondary

    # Fallback: Crush primary
    base = ColorMath.calc_color(primary, "desaturate", 55)
    if mode == "dark":
        for _ in range(40):
            if ColorMath.luminance(base) <= 0.07:
                break
            base = ColorMath.calc_color(base, "darken", 4)
    else:
        for _ in range(40):
            if ColorMath.luminance(base) >= 0.80:
                break
            base = ColorMath.calc_color(base, "lighten", 4)
    return base


def derive_accents(colors: list[str], base: str, primary: str, mode: str) -> dict:
    """
    Map team colors onto 6 accent slots.

    CRITICAL CHANGE: We now accept 'primary' explicitly.
    If 'base' is black/grey, we DO NOT derive accents from 'base'.
    We derive them from 'primary' (Orange) to ensure we get color.
    """
    boost_dir = "lighten" if mode == "dark" else "darken"
    target    = 3.0

    # If we have real colors, use them. If not, fall back to primary.
    real = [c for c in colors if _is_real_color(c)]

    # If the base is black (luminance < 0.05), we MUST use the primary color
    # as the source for accents, otherwise we get grey.
    if ColorMath.luminance(base) < 0.05 and primary:
        # Ensure primary is in the list if not already
        if primary not in real:
            real.insert(0, primary)

    if not real:
        real = ["#1a1a2e"] # Fallback if somehow empty

    # Boost contrast against the base
    boosted = [ColorMath.auto_boost(c, base, target, boost_dir) for c in real]

    def sibling(color: str, desat: float, nudge: float) -> str:
        c = ColorMath.calc_color(color, "desaturate", desat)
        c = ColorMath.calc_color(c, boost_dir, nudge)
        return ColorMath.auto_boost(c, base, target, boost_dir)

    n = len(boosted)

    # Primary trio — team colors, or progressively muted anchor to fill gaps
    # If we have the primary orange, it should be the first accent (IRIS)
    iris = boosted[0]
    love = boosted[1] if n >= 2 else sibling(iris, 30, 10)
    gold = boosted[2] if n >= 3 else sibling(iris, 50, 20)

    # Shadow trio — extra team colors, or mild same-hue siblings of primary
    pine = boosted[3] if n >= 4 else sibling(iris, 15, 6)
    foam = boosted[4] if n >= 5 else sibling(love, 15, 6)
    rose = boosted[5] if n >= 6 else sibling(gold, 15, 6)

    return {"IRIS": iris, "LOVE": love, "GOLD": gold, "PINE": pine, "FOAM": foam, "ROSE": rose}



def build_full_palette(base: str, accents: dict, mode: str) -> dict:
    """
    Derive the structural palette (surface/overlay/text tiers, waybar tiers,
    gradients, etc.) — mirrors ThemeGenerator.calculate_palette().
    """
    p = {}
    p["BASE"] = base

    if mode == "dark":
        p["SURFACE"]        = ColorMath.calc_color(base, "lighten", 10)
        p["OVERLAY"]        = ColorMath.calc_color(base, "lighten", 20)
        p["HIGHLIGHT_LOW"]  = ColorMath.calc_color(base, "lighten",  5)
        p["HIGHLIGHT_MED"]  = ColorMath.calc_color(base, "lighten", 12)
        p["HIGHLIGHT_HIGH"] = ColorMath.calc_color(base, "lighten", 25)
        p["MUTED"]          = ColorMath.calc_color(ColorMath.calc_color(base, "desaturate", 40), "lighten", 30)
        p["SUBTLE"]         = ColorMath.calc_color(ColorMath.calc_color(base, "desaturate", 50), "lighten", 40)
        p["TEXT"]           = "#ffffff"
        p["INACTIVE_BORDER"]= ColorMath.calc_color(ColorMath.calc_color(base, "desaturate", 20), "lighten", 12)
        p["SHADOW"]         = ColorMath.calc_color(ColorMath.calc_color(base, "desaturate", 30), "darken",   8)
        p["WB_BASE"]        = ColorMath.calc_color(base, "lighten",  7)
        p["WB_SURFACE"]     = ColorMath.calc_color(base, "lighten", 11)
        p["WB_OVERLAY"]     = ColorMath.calc_color(base, "lighten", 16)
    else:
        p["SURFACE"]        = ColorMath.calc_color(base, "darken", 10)
        p["OVERLAY"]        = ColorMath.calc_color(base, "darken", 20)
        p["HIGHLIGHT_LOW"]  = ColorMath.calc_color(base, "darken",  5)
        p["HIGHLIGHT_MED"]  = ColorMath.calc_color(base, "darken", 12)
        p["HIGHLIGHT_HIGH"] = ColorMath.calc_color(base, "darken", 25)
        p["MUTED"]          = ColorMath.calc_color(ColorMath.calc_color(base, "desaturate", 40), "darken", 30)
        p["SUBTLE"]         = ColorMath.calc_color(ColorMath.calc_color(base, "desaturate", 50), "darken", 40)
        p["TEXT"]           = "#1a1a1a"
        p["INACTIVE_BORDER"]= ColorMath.calc_color(ColorMath.calc_color(base, "desaturate", 25), "darken", 10)
        p["SHADOW"]         = ColorMath.calc_color(ColorMath.calc_color(base, "desaturate", 35), "darken", 20)
        p["WB_BASE"]        = ColorMath.calc_color(base, "darken",  5)
        p["WB_SURFACE"]     = ColorMath.calc_color(base, "darken",  8)
        p["WB_OVERLAY"]     = ColorMath.calc_color(base, "darken", 12)

    p.update(accents)

    # Gradient anchors
    for tier, key in [("WB_BASE", "BASE"), ("WB_SURFACE", "SURFACE"), ("WB_OVERLAY", "OVERLAY")]:
        p[f"GRAD_{key}_HI"] = ColorMath.calc_color(p[tier], "lighten", 3)
        p[f"GRAD_{key}_LO"] = ColorMath.calc_color(p[tier], "darken",  3)

    # RGB triples for rgba() compositing
    p["SHADOW_RGB"]          = ColorMath.hex_to_rgb_csv(p["SHADOW"])
    p["BORDER_ACCENT_RGB"]   = ColorMath.hex_to_rgb_csv(accents["LOVE"])
    p["BORDER_IRIS_RGB"]     = ColorMath.hex_to_rgb_csv(accents["IRIS"])

    # State colors derived from LOVE
    p["CRITICAL"]    = ColorMath.calc_color(accents["LOVE"], "shift_hue", -10)
    p["WARNING"]     = ColorMath.calc_color(accents["LOVE"], "shift_hue",  35)
    p["CAUTION"]     = ColorMath.calc_color(accents["LOVE"], "lighten",    20)
    p["MUTED_ICON"]  = ColorMath.calc_color(ColorMath.calc_color(base, "desaturate", 20), "lighten", 15)

    # Battery semantic mapping
    p["BATTERY_CRIT"] = accents["LOVE"]
    p["BATTERY_LOW"]  = accents["GOLD"]
    p["BATTERY_MED"]  = accents["ROSE"]
    p["BATTERY_HIGH"] = accents["FOAM"]
    p["BATTERY_FULL"] = accents["PINE"]

    # Tinted backgrounds
    p["TINT_PINE_DARK"]   = ColorMath.calc_color(accents["PINE"],     "lighten", 85)
    p["TINT_PINE_MID"]    = ColorMath.calc_color(accents["PINE"],     "lighten", 90)
    p["TINT_CRITICAL_BG"] = ColorMath.calc_color(p["CRITICAL"],       "lighten", 85)

    # Hover backgrounds
    p["HOVER_MUTED_BG"]  = ColorMath.calc_color(p["MUTED"],           "lighten", 15)
    p["HOVER_TEAL_BG"]   = ColorMath.calc_color(accents["FOAM"],      "lighten", 15)
    p["HOVER_GREEN_BG"]  = ColorMath.calc_color(accents["PINE"],      "lighten", 15)
    p["HOVER_GOLD_BG"]   = ColorMath.calc_color(accents["GOLD"],      "lighten", 15)
    p["HOVER_ORANGE_BG"] = ColorMath.calc_color(p["WARNING"],         "lighten", 15)

    # Named roles
    p["BORDER_ACCENT"]   = ColorMath.calc_color(accents["LOVE"], "darken", 10)
    p["ACCENT_PRIMARY"]  = accents["IRIS"]
    p["ACCENT_SECONDARY"]= ColorMath.calc_color(
        ColorMath.calc_color(accents["IRIS"], "shift_hue", 30), "desaturate", 15
    )
    p["TEXT_PRIMARY"]    = p["TEXT"]
    p["TEXT_SECONDARY"]  = p["SUBTLE"]

    # Typography constants (fixed)
    p["FONT_SIZE_BAR"] = "12px"
    p["ICON_SHADOW"]   = "0 1px 2px rgba(0,0,0,0.80)"
    p["SHADOW_A_OUTER"] = "0.50"
    p["SHADOW_A_DROP"]  = "0.55"
    p["SHADOW_A_HOVER"] = "0.65"
    p["INSET_TOP_A"]    = "0.08"
    p["INSET_BOT_A"]    = "0.30"
    p["BORDER_TOP_A"]   = "0.07"

    return p


def enrich_team(team: dict, mode: str = "dark") -> dict:
    primary   = (team.get("primary")   or "").strip()
    secondary = (team.get("secondary") or "").strip() or None
    tertiary  = (team.get("tertiary")  or "").strip() or None

    # Prefer the merged colors array from pull-teamcolors; fall back to p/s/t
    colors = team.get("colors") or [c for c in [primary, secondary, tertiary] if c]

    # 1. Determine Base (Secondary if valid, else crushed Primary)
    base = derive_base(primary, secondary, mode)

    # 2. Determine Accents (Always driven by Primary if Base is dark/grey)
    # Pass 'primary' explicitly so derive_accents knows where to get the hue
    accents = derive_accents(colors, base, primary, mode)

    palette = build_full_palette(base, accents, mode)

    return {**team, "palette": palette}

# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--in",  dest="src", default="teamcolors.json")
    parser.add_argument("--out", dest="dst", default="teamcolors-full.json")
    parser.add_argument("--mode", choices=["dark", "light"], default="dark")
    parser.add_argument("--team", help="Only enrich this team name (substring match)")
    args = parser.parse_args()

    src = Path(args.src)
    if not src.exists():
        sys.exit(f"Not found: {src}")

    teams = json.loads(src.read_text())

    if args.team:
        teams = [t for t in teams if args.team.lower() in t["name"].lower()]

    enriched = []
    for team in teams:
        try:
            enriched.append(enrich_team(team, args.mode))
        except Exception as e:
            print(f"  SKIP {team['name']}: {e}", file=sys.stderr)

    Path(args.dst).write_text(json.dumps(enriched, indent=2))
    print(f"{len(enriched)} teams enriched → {args.dst}")

    # Spot-print a sample
    if enriched:
        sample = enriched[0]
        p = sample["palette"]
        print(f"\nSample — {sample['name']} ({sample['league']})")
        print(f"  BASE   {p['BASE']}  IRIS {p['IRIS']}  LOVE {p['LOVE']}")
        print(f"  FOAM   {p['FOAM']}  PINE {p['PINE']}  GOLD {p['GOLD']}  ROSE {p['ROSE']}")
        print(f"  contrast IRIS vs BASE: {ColorMath.contrast(p['IRIS'], p['BASE']):.1f}:1")
        print(f"  contrast LOVE vs BASE: {ColorMath.contrast(p['LOVE'], p['BASE']):.1f}:1")


if __name__ == "__main__":
    main()
