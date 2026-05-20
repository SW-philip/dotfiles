#!/usr/bin/env python3
"""
gen-lix-theme.py - Python prototype for generating Lix color themes
Equivalent to gen-lix-theme.sh
"""

import argparse
import io
import os
import re
import subprocess
import sys
import colorsys
from pathlib import Path
from typing import Tuple, Optional, List


# ─── ColorHunt source ─────────────────────────────────────────────────────────

def parse_colorhunt_url(url: str) -> List[str]:
    """
    Extract 4 hex colors from a colorhunt.co palette URL.
    The slug is 4×6-char hex codes concatenated: no HTTP needed.
    e.g. colorhunt.co/palette/222831393e4600adb5eeeeee → ['#222831','#393e46','#00adb5','#eeeeee']
    """
    slug = url.rstrip("/").split("/")[-1]
    if not re.fullmatch(r"[0-9a-fA-F]{24}", slug):
        raise ValueError(f"Not a valid ColorHunt palette slug: {slug!r} (expected 24 hex chars)")
    return [f"#{slug[i:i+6].lower()}" for i in range(0, 24, 6)]


def map_colorhunt_to_slots(colors: List[str]) -> List[Optional[str]]:
    """
    Map 4 ColorHunt colors onto the 7 theme slots:
        [BASE, LOVE, ROSE, PINE, FOAM, IRIS, GOLD]

    Called before the TUI opens; slots left as None are picked interactively.

    The strategy: luminance-detect BASE, assign remaining 3 (in palette order)
    to LOVE/PINE/IRIS. ROSE, FOAM, GOLD are left None for TUI picking — those
    secondary accents aren't represented in a 4-color colorhunt palette anyway.
    """
    by_lum = sorted(colors, key=ColorMath.relative_luminance)
    # Dark theme if the darkest color is clearly a background shade
    base = by_lum[0] if ColorMath.relative_luminance(by_lum[0]) < 0.2 else by_lum[-1]
    base_idx = colors.index(base)
    accents = [c for i, c in enumerate(colors) if i != base_idx]

    slots: List[Optional[str]] = [None] * 7
    slots[0] = base        # BASE
    slots[1] = accents[0]  # LOVE
    slots[3] = accents[1]  # PINE
    slots[5] = accents[2]  # IRIS
    # ROSE (2), FOAM (4), GOLD (6) → picked in TUI
    return slots

from PIL import Image, ImageDraw, ImageChops

# ─── Optional TUI color picker ────────────────────────────────────────────────
# Install: uv add textual  OR  add python3Packages.textual to your nix env
try:
    from textual.app import App, ComposeResult
    from textual.binding import Binding
    from textual.containers import Horizontal, Vertical
    from textual.reactive import reactive
    from textual.widget import Widget
    from textual.widgets import Footer, Header, Input, Label, Static
    from rich.text import Text as RText
    from rich.style import Style as RStyle
    from rich.color import Color as RColor
    _TUI = True
except ImportError:
    _TUI = False

# ─── Optional SVG wallpaper rendering ─────────────────────────────────────────
try:
    import cairosvg as _cairosvg
    _CAIROSVG = True
except ImportError:
    _CAIROSVG = False

if _TUI:
    _NAMES = ["Base",  "Love",      "Rose",  "Pine",  "Foam",    "Iris",        "Gold"]
    _DESCS = ["bg",    "red/warm",  "pink",  "green", "seafoam", "blue/purple", "warm/yellow"]
    _GW    = 40   # saturation columns
    _GH    = 16   # value rows
    _HW    = 40   # hue strip columns
    _CELL  = "  "

    def _hsv2hex(h, s, v):
        r, g, b = colorsys.hsv_to_rgb(h, s, v)
        return f"#{int(r*255):02x}{int(g*255):02x}{int(b*255):02x}"

    def _hex2hsv(c):
        c = c.lstrip('#')
        r, g, b = (int(c[i:i+2], 16) / 255.0 for i in (0, 2, 4))
        return colorsys.rgb_to_hsv(r, g, b)

    def _bg(hex_c):
        h = hex_c.lstrip('#')
        return RStyle(bgcolor=RColor.from_rgb(int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)))


    class _HueBar(Widget):
        """Rainbow hue strip with ▲ cursor."""
        hue: reactive[float] = reactive(0.0)

        def render(self) -> RText:
            t = RText(no_wrap=True, overflow="fold")
            ci = round(self.hue * (_HW - 1))
            for i in range(_HW):
                r, g, b = colorsys.hsv_to_rgb(i / (_HW - 1), 1.0, 1.0)
                st = RStyle(bgcolor=RColor.from_rgb(int(r*255), int(g*255), int(b*255)))
                t.append("▲▲" if i == ci else _CELL, style=st)
            return t


    class _ColorGrid(Widget):
        """Saturation (x) × Value (y) grid at current hue."""
        can_focus = True
        hue: reactive[float] = reactive(0.0)
        sat: reactive[float] = reactive(0.8)
        val: reactive[float] = reactive(0.7)
        base_hex: reactive[str] = reactive("")   # set when BASE slot is filled

        def current_hex(self):
            return _hsv2hex(self.hue, self.sat, self.val)

        def render(self) -> RText:
            t = RText(no_wrap=True, overflow="fold")
            cx = round(self.sat * (_GW - 1))
            cy = round((1.0 - self.val) * (_GH - 1))
            for y in range(_GH):
                for x in range(_GW):
                    h_val, s_val, v_val = self.hue, x / (_GW - 1), 1 - y / (_GH - 1)
                    r, g, b = colorsys.hsv_to_rgb(h_val, s_val, v_val)
                    # Dim cells below 3:1 contrast vs BASE (accent slots only)
                    if self.base_hex:
                        cell_hex = f"#{int(r*255):02x}{int(g*255):02x}{int(b*255):02x}"
                        if ColorMath.contrast_ratio(cell_hex, self.base_hex) < 3.0:
                            r, g, b = r * 0.3, g * 0.3, b * 0.3
                    st = RStyle(bgcolor=RColor.from_rgb(int(r*255), int(g*255), int(b*255)))
                    t.append("◆◆" if (x == cx and y == cy) else _CELL, style=st)
                t.append("\n")
            return t


    class _Slots(Widget):
        """Left panel: 7 color slots with swatches."""
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self._slot = 0
            self._cols: list = [None] * 7

        def set_state(self, slot: int, cols: list) -> None:
            self._slot = slot
            self._cols = list(cols)
            self.refresh()

        def render(self) -> RText:
            t = RText()
            cols = list(self._cols)
            while len(cols) < 7:
                cols.append(None)
            for i, (name, desc) in enumerate(zip(_NAMES, _DESCS)):
                active = i == self._slot
                hex_c  = cols[i]
                sw_st  = _bg(hex_c) if hex_c else RStyle(bgcolor=RColor.from_rgb(40, 40, 40))
                row_st = "bold white" if active else ("green" if hex_c else "dim")
                t.append(f"{'▶' if active else ' '} {name:<4} ", style=row_st)
                t.append(_CELL, style=sw_st)
                t.append(f" {hex_c}\n" if hex_c else f" {desc}\n", style="dim")
            return t


    class ThemePickerApp(App):
        """TUI replacement for get_inputs_interactive()."""

        CSS = """
        Screen { layout: vertical; }
        #wrap  { layout: horizontal; height: 1fr; }
        #left  { width: 26; padding: 1; border-right: solid $primary-background-lighten-2; }
        #right { layout: vertical; padding: 0 2; }
        #hue   { height: 1; margin: 1 0; }
        #grid  { height: 16; }
        #bar   { layout: horizontal; height: 3; margin-top: 1; align: left middle; }
        #prev  { width: 10; height: 1; }
        #hexin { width: 16; margin-left: 1; }
        #ratio { color: $text-muted; margin-left: 2; }
        #elab  { color: $warning; margin: 1 0; }
        #keys  { color: $text-muted; margin-bottom: 1; }
        """

        BINDINGS = [
            Binding("left",      "h_dec", "Hue ←",  show=False),
            Binding("right",     "h_inc", "Hue →",  show=False),
            Binding("up",        "v_inc", "Val ↑",  show=False),
            Binding("down",      "v_dec", "Val ↓",  show=False),
            Binding("comma",     "s_dec", "Sat ,",  show=False),
            Binding("full_stop", "s_inc", "Sat .",  show=False),
            Binding("tab",       "nxt",   "Next slot"),
            Binding("shift+tab", "prv",   "Prev slot", show=False),
            Binding("space",     "pick",  "Pick color"),
            Binding("ctrl+g",    "gen",   "Generate"),
            Binding("escape",    "bye",   "Cancel"),
        ]

        def __init__(self, name0="", initial_cols=None):
            super().__init__()
            self._name0 = name0
            self._h = 0.0
            self._s = 0.8
            self._v = 0.7
            self._cols: list = list(initial_cols) if initial_cols else [None] * 7
            self.result: Optional[dict] = None
            # Start on the first unfilled slot
            self._slot = next((i for i, c in enumerate(self._cols) if c is None), 0)
            # Seed picker position from pre-filled slot if all slots are filled
            if self._cols[self._slot]:
                self._h, self._s, self._v = _hex2hsv(self._cols[self._slot])

        def compose(self) -> ComposeResult:
            yield Header(show_clock=False)
            with Horizontal(id="wrap"):
                with Vertical(id="left"):
                    yield Label("Theme name:")
                    yield Input(value=self._name0, id="namein", placeholder="my-theme")
                    yield Label("", id="elab")
                    yield Label("Colors:")
                    yield _Slots(id="slots")
                with Vertical(id="right"):
                    yield Label(
                        "← → hue   , . sat   ↑ ↓ val   "
                        "Space=pick   Tab=next slot   Ctrl+G=done   Esc=cancel",
                        id="keys",
                    )
                    yield _HueBar(id="hue")
                    yield _ColorGrid(id="grid")
                    with Horizontal(id="bar"):
                        yield Static("", id="prev")
                        yield Input(id="hexin", placeholder="#rrggbb", max_length=7)
                        yield Label("", id="ratio")
            yield Footer()

        def on_mount(self):
            self.query_one("#grid").focus()
            self._sync()

        def _sync(self):
            grid = self.query_one("#grid", _ColorGrid)
            grid.hue, grid.sat, grid.val = self._h, self._s, self._v
            self.query_one("#hue", _HueBar).hue = self._h
            self.query_one("#slots", _Slots).set_state(self._slot, self._cols)
            self.query_one("#elab", Label).update(f"Editing: {_NAMES[self._slot]}")
            try:
                self.query_one("#prev", Static).update(
                    RText(_CELL * 5, style=_bg(grid.current_hex()))
                )
            except Exception:
                pass
            base = self._cols[0]
            self.query_one("#grid", _ColorGrid).base_hex = base if (self._slot > 0 and base) else ""
            try:
                cur = grid.current_hex()
                if self._slot == 0:
                    _, s, _ = _hex2hsv(cur)
                    label = f"sat {s*100:.0f}%  (lower = more neutral)"
                else:
                    if base:
                        ratio = ColorMath.contrast_ratio(cur, base)
                        mark = "✓" if ratio >= 3.0 else "✗"
                        label = f"{ratio:.1f}:1 {mark} vs BASE"
                    else:
                        label = "pick BASE first"
                self.query_one("#ratio", Label).update(label)
            except Exception:
                pass

        def action_h_dec(self): self._h = max(0.0, self._h - 1/(_HW-1)); self._sync()
        def action_h_inc(self): self._h = min(1.0, self._h + 1/(_HW-1)); self._sync()
        def action_v_inc(self): self._v = min(1.0, self._v + 1/(_GH-1)); self._sync()
        def action_v_dec(self): self._v = max(0.0, self._v - 1/(_GH-1)); self._sync()
        def action_s_dec(self): self._s = max(0.0, self._s - 1/(_GW-1)); self._sync()
        def action_s_inc(self): self._s = min(1.0, self._s + 1/(_GW-1)); self._sync()

        def action_nxt(self):
            self._slot = (self._slot + 1) % 7
            c = self._cols[self._slot]
            if c:
                self._h, self._s, self._v = _hex2hsv(c)
            self._sync()

        def action_prv(self):
            self._slot = (self._slot - 1) % 7
            c = self._cols[self._slot]
            if c:
                self._h, self._s, self._v = _hex2hsv(c)
            self._sync()

        def action_pick(self):
            hex_c = self.query_one("#grid", _ColorGrid).current_hex()
            # Guard: accent slots must not duplicate BASE (contrast < 1.5:1)
            if self._slot > 0 and self._cols[0]:
                ratio = ColorMath.contrast_ratio(hex_c, self._cols[0])
                if ratio < 1.5:
                    self.notify("Too similar to BASE — pick something with more contrast", severity="warning")
                    return
            self._cols[self._slot] = hex_c
            for off in range(1, 8):
                ni = (self._slot + off) % 7
                if self._cols[ni] is None:
                    self._slot = ni
                    self._sync()
                    return
            self._slot = (self._slot + 1) % 7
            self._sync()

        def on_input_submitted(self, event: Input.Submitted):
            if event.input.id != "hexin":
                return
            raw = event.value.strip()
            val = raw if raw.startswith('#') else f"#{raw}"
            if re.match(r'^#[0-9a-fA-F]{6}$', val):
                if self._slot > 0 and self._cols[0]:
                    ratio = ColorMath.contrast_ratio(val.lower(), self._cols[0])
                    if ratio < 1.5:
                        self.notify("Too similar to BASE — needs more contrast", severity="warning")
                        event.input.value = ""
                        return
                self._cols[self._slot] = val.lower()
                self._h, self._s, self._v = _hex2hsv(val)
                event.input.value = ""
                self.query_one("#grid").focus()
                self.action_nxt()
            else:
                self.notify(f"Bad hex: {raw!r}", severity="warning")

        def action_gen(self):
            name = self.query_one("#namein", Input).value.strip()
            if not name:
                self.notify("Enter a theme name!", severity="warning")
                return
            missing = [_NAMES[i] for i, c in enumerate(self._cols) if c is None]
            if missing:
                self.notify(f"Still need: {', '.join(missing)}", severity="warning")
                return
            self.result = dict(
                theme_name=name,
                primary=self._cols[0],   # BASE
                secondary=self._cols[1], # LOVE
                rose=self._cols[2],      # ROSE (direct)
                pine=self._cols[3],      # PINE
                foam=self._cols[4],      # FOAM (direct)
                accent=self._cols[5],    # IRIS
                gold=self._cols[6],      # GOLD
            )
            self.exit()

        def action_bye(self):
            self.exit()


    def _tui_pick(name0="", initial_cols=None) -> Optional[dict]:
        app = ThemePickerApp(name0, initial_cols=initial_cols)
        app.run()
        return app.result


class ColorMath:
    """Color conversion and manipulation utilities."""

    @staticmethod
    def hex_to_rgb(hex_color: str) -> Tuple[int, int, int]:
        """Convert hex color to RGB tuple."""
        hex_color = hex_color.lstrip('#')
        return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

    @staticmethod
    def rgb_to_hex(r: int, g: int, b: int) -> str:
        """Convert RGB to hex color."""
        return f"#{r:02x}{g:02x}{b:02x}"

    @staticmethod
    def hex_to_rgb_csv(hex_color: str) -> str:
        """Convert hex to RGB CSV for rgba() usage."""
        r, g, b = ColorMath.hex_to_rgb(hex_color)
        return f"{r},{g},{b}"

    @staticmethod
    def _rgb_to_hsl(r: int, g: int, b: int) -> Tuple[float, float, float]:
        """Convert RGB to HSL (H: 0-360, S: 0-1, L: 0-1)."""
        r_n, g_n, b_n = r / 255.0, g / 255.0, b / 255.0

        max_c = max(r_n, g_n, b_n)
        min_c = min(r_n, g_n, b_n)
        l = (max_c + min_c) / 2.0

        if max_c == min_c:
            h = s = 0.0
        else:
            d = max_c - min_c
            s = d / (2.0 - max_c - min_c) if l > 0.5 else d / (max_c + min_c)

            if max_c == r_n:
                h = (g_n - b_n) / d + (6.0 if g_n < b_n else 0.0)
            elif max_c == g_n:
                h = (b_n - r_n) / d + 2.0
            else:
                h = (r_n - g_n) / d + 4.0
            h /= 6.0

        return (h * 360.0, s, l)

    @staticmethod
    def _hsl_to_rgb(h: float, s: float, l: float) -> Tuple[int, int, int]:
        """Convert HSL to RGB (H: 0-360, S: 0-1, L: 0-1)."""
        h_norm = h / 360.0

        if s == 0:
            r = g = b = l
        else:
            q = l * (1 + s) if l < 0.5 else l + s - l * s
            p = 2 * l - q

            def hue_to_rgb(t):
                if t < 0: t += 1
                if t > 1: t -= 1
                if t < 1/6: return p + (q - p) * 6 * t
                if t < 1/2: return q
                if t < 2/3: return p + (q - p) * (2/3 - t) * 6
                return p

            r = hue_to_rgb(h_norm + 1/3)
            g = hue_to_rgb(h_norm)
            b = hue_to_rgb(h_norm - 1/3)

        return (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))

    @staticmethod
    def calc_color(hex_color: str, operation: str, amount: float) -> str:
        """
        Calculate modified color.
        operations: lighten, darken, desaturate, saturate, shift_hue
        amount: percentage (0-100) for light/dark/sat, degrees for hue
        """
        r, g, b = ColorMath.hex_to_rgb(hex_color)
        h, s, l = ColorMath._rgb_to_hsl(r, g, b)

        if operation == "lighten":
            l = min(1.0, l + amount / 100.0)
        elif operation == "darken":
            l = max(0.0, l - amount / 100.0)
        elif operation == "desaturate":
            s = s * (1 - amount / 100.0)
        elif operation == "saturate":
            s = s + (1 - s) * amount / 100.0
        elif operation == "shift_hue":
            h = (h + amount) % 360

        new_r, new_g, new_b = ColorMath._hsl_to_rgb(h, s, l)
        return ColorMath.rgb_to_hex(new_r, new_g, new_b)

    @staticmethod
    def _linearize(c: float) -> float:
        """Linearize sRGB component for luminance calculation."""
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    @staticmethod
    def relative_luminance(hex_color: str) -> float:
        """Calculate WCAG relative luminance."""
        r, g, b = ColorMath.hex_to_rgb(hex_color)
        r_lin = ColorMath._linearize(r / 255.0)
        g_lin = ColorMath._linearize(g / 255.0)
        b_lin = ColorMath._linearize(b / 255.0)
        return 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin

    @staticmethod
    def contrast_ratio(hex1: str, hex2: str) -> float:
        """Calculate WCAG contrast ratio between two colors."""
        l1 = ColorMath.relative_luminance(hex1)
        l2 = ColorMath.relative_luminance(hex2)
        if l1 < l2:
            l1, l2 = l2, l1
        return (l1 + 0.05) / (l2 + 0.05)

    @staticmethod
    def get_hue(hex_color: str) -> int:
        """Get hue angle (0-359) for a color."""
        r, g, b = ColorMath.hex_to_rgb(hex_color)
        h, _, _ = ColorMath._rgb_to_hsl(r, g, b)
        return int(round(h))

    @staticmethod
    def get_text_color(hex_color: str) -> str:
        """Determine text color based on brightness."""
        r, g, b = ColorMath.hex_to_rgb(hex_color)
        brightness = (r * 299 + g * 587 + b * 114) // 1000
        return "#1a1a1a" if brightness > 155 else "#ffffff"

    @staticmethod
    def theme_mode(hex_color: str) -> str:
        """Determine if theme is dark or light based on base color."""
        r, g, b = ColorMath.hex_to_rgb(hex_color)
        brightness = (r * 299 + g * 587 + b * 114) // 1000
        return "dark" if brightness < 128 else "light"


class ThemeGenerator:
    """Main theme generation class."""

    DEFAULT_FOLDER = "Lix"
    HEX_PATTERN = re.compile(r'^#[0-9a-fA-F]{6}$')

    def __init__(self, folder: Optional[str] = None, theme_name: Optional[str] = None,
                 primary: Optional[str] = None, secondary: Optional[str] = None,
                 pine: Optional[str] = None, accent: Optional[str] = None,
                 gold: Optional[str] = None, rose: Optional[str] = None,
                 foam: Optional[str] = None, initial_cols: Optional[List] = None):
        self.folder = folder or self.DEFAULT_FOLDER
        self.theme_name = theme_name
        self.primary_color = primary
        self.secondary_color = secondary
        self.pine_color = pine
        self.accent_color = accent
        self.gold_color = gold
        self.rose_color = rose
        self.foam_color = foam
        self.initial_cols = initial_cols  # pre-populated from a color source (e.g. ColorHunt)
        self.script_dir = Path(__file__).parent.resolve()
        self.harmonizer = self.script_dir / "harmonize-themes.sh"

    def validate_hex(self, color: str) -> bool:
        """Validate hex color format."""
        return bool(self.HEX_PATTERN.match(color))

    def get_inputs_interactive(self):
        """Prompt for inputs if not provided via CLI args."""
        # If all inputs already supplied (e.g. via CLI), skip interactive prompts
        if all([self.theme_name, self.primary_color, self.secondary_color,
                self.rose_color, self.pine_color, self.foam_color,
                self.accent_color, self.gold_color]):
            return
        if _TUI:
            result = _tui_pick(self.theme_name or "", initial_cols=self.initial_cols)
            if result is None:
                print("Cancelled.")
                sys.exit(0)
            self.theme_name      = result["theme_name"]
            self.primary_color   = result["primary"]
            self.secondary_color = result["secondary"]
            self.rose_color      = result["rose"]
            self.pine_color      = result["pine"]
            self.foam_color      = result["foam"]
            self.accent_color    = result["accent"]
            self.gold_color      = result["gold"]
            return

        # Fallback: plain prompts when textual is not installed
        if not self.theme_name:
            self.theme_name = input("🎨 Enter Theme Name: ").strip()
        if not self.primary_color:
            self.primary_color = input("🎨 Enter Primary Color / Base (Hex): ").strip()
        if not self.secondary_color:
            self.secondary_color = input("🎨 Enter Love / Secondary Color (Hex): ").strip()
        if not self.rose_color:
            self.rose_color = input("🌸 Enter Rose / Pink Color (Hex): ").strip()
        if not self.pine_color:
            self.pine_color = input("🌲 Enter Pine / Green Color (Hex): ").strip()
        if not self.foam_color:
            self.foam_color = input("🌊 Enter Foam / Seafoam Color (Hex): ").strip()
        if not self.accent_color:
            self.accent_color = input("🔮 Enter Iris / Accent Color (Hex): ").strip()
        if not self.gold_color:
            self.gold_color = input("✨ Enter Gold / Warm Color (Hex): ").strip()

    def validate_inputs(self) -> bool:
        """Validate all required inputs."""
        if not all([self.theme_name, self.primary_color,
                    self.secondary_color, self.rose_color, self.pine_color,
                    self.foam_color, self.accent_color, self.gold_color]):
            print("❌ Error: Missing required inputs.")
            return False

        for col in [self.primary_color, self.secondary_color,
                    self.rose_color, self.pine_color, self.foam_color,
                    self.accent_color, self.gold_color]:
            if not self.validate_hex(col):
                print(f"❌ Error: '{col}' is not a valid Hex color (e.g., #RRGGBB).")
                return False

        return True

    def setup_paths(self) -> Tuple[Path, Path, str, Path]:
        """Create directory structure and return paths."""
        slug = re.sub(r'([a-z0-9])([A-Z])', r'\1-\2', self.theme_name).lower()

        base_path = Path.home() / "nixos" / "themes" / self.folder
        theme_dir = base_path / self.theme_name

        base_path.mkdir(parents=True, exist_ok=True)
        theme_dir.mkdir(parents=True, exist_ok=True)

        palette_nix = theme_dir / f"palette-{slug}.nix"
        palette_sh = theme_dir / f"palette-{slug}.sh"

        return palette_nix, palette_sh, slug, theme_dir

    def auto_boost(self, color: str, bg: str, target: float, direction: str,
                   max_iter: int = 20) -> str:
        """Auto-adjust color to meet contrast ratio."""
        current = color
        step = 3

        for _ in range(max_iter):
            ratio = ColorMath.contrast_ratio(current, bg)
            if ratio >= target:
                return current

            adjusted = ColorMath.calc_color(current, direction, step)
            current = adjusted

        final_ratio = ColorMath.contrast_ratio(current, bg)
        print(f"⚠️  Could not reach {target}:1 for {color} vs {bg} (best: {final_ratio:.2f}:1)",
              file=sys.stderr)
        return current

    def validate_and_adjust_colors(self, mode: str):
        """Validate contrast ratios and auto-adjust if needed."""
        print("🔍 Validating contrast ratios...")

        boost_dir = "lighten" if mode == "dark" else "darken"

        # Secondary vs Primary (4.5:1)
        sec_ratio = ColorMath.contrast_ratio(self.secondary_color, self.primary_color)
        print(f"   Secondary vs Primary: {sec_ratio:.2f}:1  (target ≥4.5)")
        if sec_ratio < 4.5:
            print("   ⚡ Boosting secondary to meet 4.5:1...")
            self.secondary_color = self.auto_boost(
                self.secondary_color, self.primary_color, 4.5, boost_dir
            )
            print(f"   → {self.secondary_color}  ({ColorMath.contrast_ratio(self.secondary_color, self.primary_color):.2f}:1)")

        # Pine vs Primary (3.0:1)
        pine_ratio = ColorMath.contrast_ratio(self.pine_color, self.primary_color)
        print(f"   Pine vs Primary:      {pine_ratio:.2f}:1  (target ≥3.0)")
        if pine_ratio < 3.0:
            print("   ⚡ Boosting pine to meet 3.0:1...")
            self.pine_color = self.auto_boost(
                self.pine_color, self.primary_color, 3.0, boost_dir
            )
            print(f"   → {self.pine_color}  ({ColorMath.contrast_ratio(self.pine_color, self.primary_color):.2f}:1)")

        # Rose vs Primary (3.0:1)
        rose_ratio = ColorMath.contrast_ratio(self.rose_color, self.primary_color)
        print(f"   Rose vs Primary:      {rose_ratio:.2f}:1  (target ≥3.0)")
        if rose_ratio < 3.0:
            print("   ⚡ Boosting rose to meet 3.0:1...")
            self.rose_color = self.auto_boost(
                self.rose_color, self.primary_color, 3.0, boost_dir
            )
            print(f"   → {self.rose_color}  ({ColorMath.contrast_ratio(self.rose_color, self.primary_color):.2f}:1)")

        # Foam vs Primary (3.0:1)
        foam_ratio = ColorMath.contrast_ratio(self.foam_color, self.primary_color)
        print(f"   Foam vs Primary:      {foam_ratio:.2f}:1  (target ≥3.0)")
        if foam_ratio < 3.0:
            print("   ⚡ Boosting foam to meet 3.0:1...")
            self.foam_color = self.auto_boost(
                self.foam_color, self.primary_color, 3.0, boost_dir
            )
            print(f"   → {self.foam_color}  ({ColorMath.contrast_ratio(self.foam_color, self.primary_color):.2f}:1)")

        # Iris vs Primary (3.0:1)
        acc_ratio = ColorMath.contrast_ratio(self.accent_color, self.primary_color)
        print(f"   Iris vs Primary:      {acc_ratio:.2f}:1  (target ≥3.0)")
        if acc_ratio < 3.0:
            print("   ⚡ Boosting iris to meet 3.0:1...")
            self.accent_color = self.auto_boost(
                self.accent_color, self.primary_color, 3.0, boost_dir
            )
            print(f"   → {self.accent_color}  ({ColorMath.contrast_ratio(self.accent_color, self.primary_color):.2f}:1)")

        # Gold vs Primary (3.0:1)
        gold_ratio = ColorMath.contrast_ratio(self.gold_color, self.primary_color)
        print(f"   Gold vs Primary:      {gold_ratio:.2f}:1  (target ≥3.0)")
        if gold_ratio < 3.0:
            print("   ⚡ Boosting gold to meet 3.0:1...")
            self.gold_color = self.auto_boost(
                self.gold_color, self.primary_color, 3.0, boost_dir
            )
            print(f"   → {self.gold_color}  ({ColorMath.contrast_ratio(self.gold_color, self.primary_color):.2f}:1)")

        # Hue separation check: Love vs Iris
        hue_sec = ColorMath.get_hue(self.secondary_color)
        hue_acc = ColorMath.get_hue(self.accent_color)
        hue_diff = abs(hue_sec - hue_acc)
        if hue_diff > 180:
            hue_diff = 360 - hue_diff

        print(f"   Love hue: {hue_sec}°   Iris hue: {hue_acc}°   Separation: {hue_diff}°  (recommend ≥30°)")
        if hue_diff < 30:
            print(f"   ⚠️  Love and Iris are only {hue_diff}° apart — they may look identical on the bar.")

        print("✅ Contrast check complete.\n")

    def calculate_palette(self, mode: str) -> dict:
        """Calculate all palette colors."""
        print("🧮 Calculating harmonious palette...")
        print(f"   Theme mode: {mode}\n")

        palette = {}

        # Base-derived colors
        palette['BASE'] = self.primary_color
        palette['SURFACE'] = ColorMath.calc_color(self.primary_color, "lighten", 15)
        palette['OVERLAY'] = ColorMath.calc_color(self.primary_color, "lighten", 28)
        palette['HIGHLIGHT_LOW'] = ColorMath.calc_color(self.primary_color, "lighten", 5)
        palette['HIGHLIGHT_MED'] = ColorMath.calc_color(self.primary_color, "lighten", 10)
        palette['HIGHLIGHT_HIGH'] = ColorMath.calc_color(self.primary_color, "lighten", 20)

        palette['MUTED'] = ColorMath.calc_color(
            ColorMath.calc_color(self.primary_color, "desaturate", 40), "lighten", 30
        )
        palette['SUBTLE'] = ColorMath.calc_color(
            ColorMath.calc_color(self.primary_color, "desaturate", 50), "lighten", 40
        )
        palette['TEXT'] = ColorMath.get_text_color(self.primary_color)

        # Structural colors
        if mode == "dark":
            palette['INACTIVE_BORDER'] = ColorMath.calc_color(
                ColorMath.calc_color(self.primary_color, "desaturate", 20), "lighten", 12
            )
            palette['SHADOW'] = ColorMath.calc_color(
                ColorMath.calc_color(self.primary_color, "desaturate", 30), "darken", 8
            )
        else:
            palette['INACTIVE_BORDER'] = ColorMath.calc_color(
                ColorMath.calc_color(self.primary_color, "desaturate", 25), "darken", 10
            )
            palette['SHADOW'] = ColorMath.calc_color(
                ColorMath.calc_color(self.primary_color, "desaturate", 35), "darken", 20
            )

        palette['SHADOW_RGB'] = ColorMath.hex_to_rgb_csv(palette['SHADOW'])

        # Waybar tiers
        if mode == "dark":
            palette['WB_BASE'] = ColorMath.calc_color(self.primary_color, "lighten", 7)
            palette['WB_SURFACE'] = ColorMath.calc_color(self.primary_color, "lighten", 11)
            palette['WB_OVERLAY'] = ColorMath.calc_color(self.primary_color, "lighten", 16)
        else:
            palette['WB_BASE'] = ColorMath.calc_color(self.primary_color, "darken", 5)
            palette['WB_SURFACE'] = ColorMath.calc_color(self.primary_color, "darken", 8)
            palette['WB_OVERLAY'] = ColorMath.calc_color(self.primary_color, "darken", 12)

        # Gradient anchors
        palette['GRAD_BASE_HI'] = ColorMath.calc_color(palette['WB_BASE'], "lighten", 3)
        palette['GRAD_BASE_LO'] = ColorMath.calc_color(palette['WB_BASE'], "darken", 3)
        palette['GRAD_SURFACE_HI'] = ColorMath.calc_color(palette['WB_SURFACE'], "lighten", 3)
        palette['GRAD_SURFACE_LO'] = ColorMath.calc_color(palette['WB_SURFACE'], "darken", 3)
        palette['GRAD_OVERLAY_HI'] = ColorMath.calc_color(palette['WB_OVERLAY'], "lighten", 3)
        palette['GRAD_OVERLAY_LO'] = ColorMath.calc_color(palette['WB_OVERLAY'], "darken", 3)

        # Explicit accent colors
        palette['LOVE'] = self.secondary_color
        palette['PINE'] = self.pine_color
        palette['IRIS'] = self.accent_color
        palette['GOLD'] = self.gold_color

        # Direct: ROSE and FOAM are now user-supplied inputs
        palette['ROSE'] = self.rose_color
        palette['FOAM'] = self.foam_color

        # Iris-derived
        palette['ACCENT_SECONDARY'] = ColorMath.calc_color(
            ColorMath.calc_color(self.accent_color, "shift_hue", 30), "desaturate", 15
        )
        palette['BORDER_ACCENT'] = ColorMath.calc_color(self.secondary_color, "darken", 10)
        palette['BORDER_ACCENT_RGB'] = ColorMath.hex_to_rgb_csv(self.secondary_color)
        palette['BORDER_IRIS_RGB'] = ColorMath.hex_to_rgb_csv(self.accent_color)

        # State colors
        palette['CRITICAL'] = ColorMath.calc_color(self.secondary_color, "shift_hue", -10)
        palette['WARNING'] = ColorMath.calc_color(self.secondary_color, "shift_hue", 35)
        palette['CAUTION'] = ColorMath.calc_color(self.secondary_color, "lighten", 20)
        palette['MUTED_ICON'] = ColorMath.calc_color(
            ColorMath.calc_color(self.primary_color, "desaturate", 20), "lighten", 15
        )

        # Battery colors
        palette['BATTERY_CRIT'] = self.secondary_color
        palette['BATTERY_LOW'] = palette['GOLD']
        palette['BATTERY_MED'] = palette['ROSE']
        palette['BATTERY_HIGH'] = palette['FOAM']
        palette['BATTERY_FULL'] = palette['PINE']

        # Tinted backgrounds
        palette['TINT_PINE_DARK'] = ColorMath.calc_color(palette['PINE'], "lighten", 85)
        palette['TINT_PINE_MID'] = ColorMath.calc_color(palette['PINE'], "lighten", 90)
        palette['TINT_CRITICAL_BG'] = ColorMath.calc_color(palette['CRITICAL'], "lighten", 85)

        # Hover backgrounds
        palette['HOVER_MUTED_BG'] = ColorMath.calc_color(palette['MUTED'], "lighten", 15)
        palette['HOVER_TEAL_BG'] = ColorMath.calc_color(palette['FOAM'], "lighten", 15)
        palette['HOVER_GREEN_BG'] = ColorMath.calc_color(palette['PINE'], "lighten", 15)
        palette['HOVER_GOLD_BG'] = ColorMath.calc_color(palette['GOLD'], "lighten", 15)
        palette['HOVER_ORANGE_BG'] = ColorMath.calc_color(palette['WARNING'], "lighten", 15)

        return palette

    def generate_nix_file(self, palette: dict, slug: str, palette_nix: Path):
        """Generate the Nix palette file."""
        content = f'''{{
  # ── Base ──────────────────────────────────────────────────────
  BASE           = "{self.primary_color}";
  SURFACE        = "{palette['SURFACE']}";
  OVERLAY        = "{palette['OVERLAY']}";
  HIGHLIGHT_LOW  = "{palette['HIGHLIGHT_LOW']}";
  HIGHLIGHT_MED  = "{palette['HIGHLIGHT_MED']}";
  HIGHLIGHT_HIGH = "{palette['HIGHLIGHT_HIGH']}";

  # ── Text & accents ────────────────────────────────────────────
  MUTED  = "{palette['MUTED']}";
  SUBTLE = "{palette['SUBTLE']}";
  TEXT   = "{palette['TEXT']}";
  LOVE   = "{palette['LOVE']}";
  ROSE   = "{palette['ROSE']}";
  GOLD   = "{palette['GOLD']}";
  PINE   = "{palette['PINE']}";
  FOAM   = "{palette['FOAM']}";
  IRIS   = "{palette['IRIS']}";

  # ── Extended — named system-state colors ──────────────────────
  CRITICAL   = "{palette['CRITICAL']}";
  WARNING    = "{palette['WARNING']}";
  CAUTION    = "{palette['CAUTION']}";
  MUTED_ICON = "{palette['MUTED_ICON']}";

  # ── Structural (computed from base) ───────────────────────────
  INACTIVE_BORDER = "{palette['INACTIVE_BORDER']}";
  SHADOW          = "{palette['SHADOW']}";

  # ── Waybar module background tiers ────────────────────────────
  WB_BASE    = "{palette['WB_BASE']}";
  WB_SURFACE = "{palette['WB_SURFACE']}";
  WB_OVERLAY = "{palette['WB_OVERLAY']}";

  # ── Gradient depth anchors ────────────────────────────────────
  GRAD_SURFACE_HI = "{palette['GRAD_SURFACE_HI']}";
  GRAD_SURFACE_LO = "{palette['GRAD_SURFACE_LO']}";
  GRAD_OVERLAY_HI = "{palette['GRAD_OVERLAY_HI']}";
  GRAD_OVERLAY_LO = "{palette['GRAD_OVERLAY_LO']}";
  GRAD_BASE_HI    = "{palette['GRAD_BASE_HI']}";
  GRAD_BASE_LO    = "{palette['GRAD_BASE_LO']}";

  # ── Accent border tints (R,G,B format for rgba()) ────────────
  BORDER_ACCENT_RGB = "{palette['BORDER_ACCENT_RGB']}";
  BORDER_IRIS_RGB   = "{palette['BORDER_IRIS_RGB']}";

  # ── Derived tinted backgrounds ────────────────────────────────
  TINT_PINE_DARK   = "{palette['TINT_PINE_DARK']}";
  TINT_PINE_MID    = "{palette['TINT_PINE_MID']}";
  TINT_CRITICAL_BG = "{palette['TINT_CRITICAL_BG']}";

  # ── State-tinted hover backgrounds ────────────────────────────
  HOVER_MUTED_BG  = "{palette['HOVER_MUTED_BG']}";
  HOVER_TEAL_BG   = "{palette['HOVER_TEAL_BG']}";
  HOVER_GREEN_BG  = "{palette['HOVER_GREEN_BG']}";
  HOVER_GOLD_BG   = "{palette['HOVER_GOLD_BG']}";
  HOVER_ORANGE_BG = "{palette['HOVER_ORANGE_BG']}";

  # ── Bar typography ───────────────────────────────────────────
  FONT_SIZE_BAR = "12px";
  ICON_SHADOW   = "0 0 2px rgba(0,0,0,0.15)";

  # ── Box-shadow composition ───────────────────────────────────
  SHADOW_RGB     = "{palette['SHADOW_RGB']}";
  SHADOW_A_OUTER = "0.10";
  SHADOW_A_DROP  = "0.07";
  SHADOW_A_HOVER = "0.10";
  INSET_TOP_A    = "0.40";
  INSET_BOT_A    = "0.20";
  BORDER_TOP_A   = "0.50";

  # ── Battery (anchored to theme semantic colors) ───────────────
  BATTERY_FULL = "{palette['BATTERY_FULL']}";
  BATTERY_HIGH = "{palette['BATTERY_HIGH']}";
  BATTERY_MED  = "{palette['BATTERY_MED']}";
  BATTERY_LOW  = "{palette['BATTERY_LOW']}";
  BATTERY_CRIT = "{palette['BATTERY_CRIT']}";

  # ── Named accent roles ────────────────────────────────────────
  BORDER_ACCENT    = "{palette['BORDER_ACCENT']}";
  ACCENT_PRIMARY   = "{palette['IRIS']}";
  TEXT_PRIMARY     = "{palette['TEXT']}";
  TEXT_SECONDARY   = "{palette['SUBTLE']}";
  ACCENT_SECONDARY = "{palette['ACCENT_SECONDARY']}";
}}
'''
        palette_nix.write_text(content)
        print(f"✅ Created raw template: {palette_nix}")

    def generate_nemo_css(self, palette: dict, nemo_css: Path):
        """Generate complete Nemo file manager CSS theme."""
        content = f'''/* Nemo Theme: {self.theme_name} */
/* Generated by gen-lix-theme.py */

/* ── Base Colors ───────────────────────────────────────────────── */
@define-color nemo_base_bg {palette['BASE']};
@define-color nemo_surface_bg {palette['SURFACE']};
@define-color nemo_overlay_bg {palette['OVERLAY']};
@define-color nemo_muted {palette['MUTED']};
@define-color nemo_subtle {palette['SUBTLE']};
@define-color nemo_text {palette['TEXT']};
@define-color nemo_love {palette['LOVE']};
@define-color nemo_iris {palette['IRIS']};

/* ── Nemo Window ───────────────────────────────────────────────── */
.nemo-window {{
  background-color: @nemo_base_bg;
  color: @nemo_text;
}}

/* ── Sidebar (Places, Bookmarks) ───────────────────────────────── */
.nemo-places-sidebar,
.sidebar,
.nemo-tree-pane {{
  background-color: @nemo_surface_bg;
  color: @nemo_text;
}}

.nemo-places-sidebar .sidebar-row {{
  padding: 4px 8px;
  border-radius: 4px;
}}

.nemo-places-sidebar .sidebar-row:selected {{
  background-color: @nemo_love;
  color: @nemo_text;
}}

.nemo-places-sidebar .sidebar-row:hover {{
  background-color: @nemo_highlight_low;
}}

/* ── Main View (Icon/List) ─────────────────────────────────────── */
.nemo-window .view {{
  background-color: @nemo_base_bg;
  color: @nemo_text;
}}

.nemo-window .view:selected {{
  background-color: alpha(@nemo_love, 0.3);
  color: @nemo_text;
}}

.nemo-window .view:hover {{
  background-color: @nemo_highlight_low;
}}

/* Icon View Specific */
.nemo-window .icon-view {{
  background-color: @nemo_base_bg;
}}

.nemo-window .icon-view:selected {{
  background-color: alpha(@nemo_love, 0.3);
}}

/* List View Specific */
.nemo-window .list-view {{
  background-color: @nemo_base_bg;
}}

.nemo-window .list-view row:selected {{
  background-color: alpha(@nemo_love, 0.3);
}}

/* ── Toolbar ───────────────────────────────────────────────────── */
.nemo-window .toolbar {{
  background-color: @nemo_surface_bg;
  border-bottom: 1px solid @nemo_inactive_border;
  padding: 4px;
}}

.nemo-window .toolbar button {{
  background-color: transparent;
  border: none;
  color: @nemo_text;
  padding: 4px 8px;
  border-radius: 4px;
}}

.nemo-window .toolbar button:hover {{
  background-color: @nemo_highlight_low;
}}

.nemo-window .toolbar button:active {{
  background-color: @nemo_love;
}}

/* ── Location Bar / Path Bar ───────────────────────────────────── */
.nemo-window .path-bar {{
  background-color: @nemo_surface_bg;
}}

.nemo-window .path-bar button {{
  background-color: transparent;
  border: 1px solid @nemo_inactive_border;
  color: @nemo_text;
  padding: 4px 8px;
  border-radius: 4px;
}}

.nemo-window .path-bar button:checked {{
  background-color: @nemo_love;
  color: @nemo_text;
}}

/* ── Search Bar ────────────────────────────────────────────────── */
.nemo-window .search-bar {{
  background-color: @nemo_overlay_bg;
  border-bottom: 1px solid @nemo_inactive_border;
}}

.nemo-window .search-bar entry {{
  background-color: @nemo_base_bg;
  color: @nemo_text;
  border: 1px solid @nemo_inactive_border;
  border-radius: 4px;
  padding: 4px 8px;
}}

/* ── Status Bar ────────────────────────────────────────────────── */
.nemo-window .statusbar {{
  background-color: @nemo_surface_bg;
  color: @nemo_subtle;
  border-top: 1px solid @nemo_inactive_border;
  padding: 4px 8px;
}}

/* ── Buttons ───────────────────────────────────────────────────── */
.nemo-window button {{
  background-color: @nemo_surface_bg;
  border: 1px solid @nemo_inactive_border;
  color: @nemo_text;
  padding: 4px 12px;
  border-radius: 4px;
}}

.nemo-window button:hover {{
  background-color: @nemo_highlight_low;
}}

.nemo-window button:active {{
  background-color: @nemo_love;
}}

.nemo-window button.suggested-action {{
  background-color: @nemo_iris;
  color: @nemo_text;
}}

.nemo-window button.destructive-action {{
  background-color: @nemo_critical;
  color: @nemo_text;
}}

/* ── Entry Fields ──────────────────────────────────────────────── */
.nemo-window entry {{
  background-color: @nemo_base_bg;
  color: @nemo_text;
  border: 1px solid @nemo_inactive_border;
  border-radius: 4px;
  padding: 4px 8px;
}}

.nemo-window entry:focus {{
  border-color: @nemo_love;
}}

.nemo-window entry selection {{
  background-color: @nemo_love;
  color: @nemo_text;
}}

/* ── Scrollbars ────────────────────────────────────────────────── */
.nemo-window scrollbar trough {{
  background-color: @nemo_base_bg;
}}

.nemo-window scrollbar slider {{
  background-color: @nemo_subtle;
  border-radius: 4px;
}}

.nemo-window scrollbar slider:hover {{
  background-color: @nemo_muted;
}}

/* ── Menus ─────────────────────────────────────────────────────── */
.nemo-window menu {{
  background-color: @nemo_overlay_bg;
  border: 1px solid @nemo_inactive_border;
  border-radius: 4px;
}}

.nemo-window menu menuitem {{
  padding: 4px 8px;
  color: @nemo_text;
}}

.nemo-window menu menuitem:hover {{
  background-color: @nemo_highlight_low;
}}

.nemo-window menu menuitem:disabled {{
  color: @nemo_subtle;
}}

/* ── Context Menu ──────────────────────────────────────────────── */
.nemo-window .context-menu {{
  background-color: @nemo_overlay_bg;
  border: 1px solid @nemo_inactive_border;
}}

.nemo-window .context-menu menuitem {{
  padding: 4px 8px;
}}

.nemo-window .context-menu menuitem:hover {{
  background-color: @nemo_highlight_low;
}}

/* ── Tree View (Sidebar Tree) ──────────────────────────────────── */
.nemo-tree-view {{
  background-color: @nemo_surface_bg;
  color: @nemo_text;
}}

.nemo-tree-view:selected {{
  background-color: alpha(@nemo_love, 0.3);
}}

.nemo-tree-view:hover {{
  background-color: @nemo_highlight_low;
}}

/* ── Progress Bars ─────────────────────────────────────────────── */
.nemo-window progressbar trough {{
  background-color: @nemo_surface_bg;
  border-radius: 2px;
}}

.nemo-window progressbar progress {{
  background-color: @nemo_love;
  border-radius: 2px;
}}

/* ── Tooltips ──────────────────────────────────────────────────── */
tooltip {{
  background-color: @nemo_overlay_bg;
  color: @nemo_text;
  border: 1px solid @nemo_inactive_border;
  border-radius: 4px;
}}

/* ── Drag and Drop ─────────────────────────────────────────────── */
.nemo-window .dnd {{
  background-color: alpha(@nemo_love, 0.2);
  border: 2px dashed @nemo_love;
}}

/* ── Focus Rings ───────────────────────────────────────────────── */
.nemo-window *:focus {{
  outline: 2px solid @nemo_iris;
  outline-offset: -2px;
}}

/* ── Selection Box (for multi-select) ──────────────────────────── */
.nemo-window .selection-box {{
  background-color: alpha(@nemo_love, 0.2);
  border: 1px solid @nemo_love;
  border-radius: 4px;
}}
'''
        nemo_css.write_text(content)
        print(f"✅ Created Nemo CSS: {nemo_css}")

    def generate_wofi_css(self, palette: dict, theme_dir: Path):
        """Generate Wofi launcher CSS."""
        content = f'''/* Wofi Theme: {self.theme_name} */
/* Generated by theme-gen.py */

window {{
  background-color: {palette['BASE']};
  font-family: "JetBrainsMono Nerd Font";
  font-size: 12px;
}}

#entry {{
  margin: 5px;
  padding: 8px;
  border-radius: 6px;
  background-color: {palette['BASE']};
  color: {palette['TEXT']};
}}

#entry:selected {{
  background-color: {palette['OVERLAY']};
  color: {palette['PINE']};
}}

#input {{
  background-color: {palette['SURFACE']};
  color: {palette['TEXT']};
  border: 2px solid {palette['IRIS']};
  padding: 6px;
  margin: 5px;
}}

#text {{
  color: {palette['TEXT']};
}}

#text:selected {{
  color: {palette['PINE']};
}}
'''
        wofi_css = theme_dir / "wofi.css"
        wofi_css.write_text(content)
        print(f"✅ Created Wofi CSS: {wofi_css}")

    def generate_wvkbd_args(self, palette: dict, theme_dir: Path):
        """Generate wvkbd color args file (sourced by the systemd service at launch)."""
        strip = lambda h: h.lstrip('#')
        content = (
            f'#!/usr/bin/env bash\n'
            f'# wvkbd color args for {self.theme_name}\n'
            f'WVKBD_ARGS="'
            f'--bg {strip(palette["BASE"])} '
            f'--fg {strip(palette["WB_SURFACE"])} '
            f'--fg-sp {strip(palette["WB_OVERLAY"])} '
            f'--press {strip(palette["LOVE"])} '
            f'--press-sp {strip(palette["PINE"])} '
            f'--swipe {strip(palette["FOAM"])} '
            f'--swipe-sp {strip(palette["IRIS"])} '
            f'--text {strip(palette["TEXT"])} '
            f'--text-sp {strip(palette["SUBTLE"])}"\n'
        )
        wvkbd_sh = theme_dir / "wvkbd-colors.sh"
        wvkbd_sh.write_text(content)
        wvkbd_sh.chmod(0o755)
        print(f"✅ Created {wvkbd_sh}")

    def generate_fuzzel_ini(self, palette: dict, theme_dir: Path):
        """Generate Fuzzel launcher INI with palette colors."""
        def c(hex_color: str) -> str:
            return hex_color.lstrip('#') + "ff"

        content = f'''[main]
font=monospace:size=13
dpi-aware=auto
prompt=
terminal=ghostty -e
layer=overlay
show-actions=yes
width=35
lines=8

[colors]
background={c(palette['BASE'])}
text={c(palette['TEXT'])}
match={c(palette['IRIS'])}
selection={c(palette['OVERLAY'])}
selection-text={c(palette['ROSE'])}
selection-match={c(palette['FOAM'])}
border={c(palette['PINE'])}

[border]
width=1
radius=6
'''
        fuzzel_ini = theme_dir / "fuzzel.ini"
        fuzzel_ini.write_text(content)
        print(f"✅ Created Fuzzel INI: {fuzzel_ini}")

    def generate_shell_file(self, palette: dict, palette_sh: Path):
        """Generate the shell script palette file."""
        content = f'''#!/usr/bin/env bash
# {self.theme_name} — generated palette for waybar scripts

# ── Base colors ───────────────────────────────────────────────
BASE="{self.primary_color}"
SURFACE="{palette['SURFACE']}"
OVERLAY="{palette['OVERLAY']}"
MUTED="{palette['MUTED']}"
SUBTLE="{palette['SUBTLE']}"
TEXT="{palette['TEXT']}"

# ── Accent spectrum (from secondary) ──────────────────────────
LOVE="{palette['LOVE']}"
ROSE="{palette['ROSE']}"
GOLD="{palette['GOLD']}"
PINE="{palette['PINE']}"
FOAM="{palette['FOAM']}"
IRIS="{palette['IRIS']}"

# ── Highlight tiers ───────────────────────────────────────────
HIGHLIGHT_LOW="{palette['HIGHLIGHT_LOW']}"
HIGHLIGHT_MED="{palette['HIGHLIGHT_MED']}"
HIGHLIGHT_HIGH="{palette['HIGHLIGHT_HIGH']}"

# ── Structural ───────────────────────────────────────────────
SHADOW="{palette['SHADOW']}"
INACTIVE_BORDER="{palette['INACTIVE_BORDER']}"

# ── Waybar bar tiers ──────────────────────────────────────────
WB_BASE="{palette['WB_BASE']}"
WB_SURFACE="{palette['WB_SURFACE']}"
WB_OVERLAY="{palette['WB_OVERLAY']}"

# ── Text roles ────────────────────────────────────────────────
TEXT_PRIMARY="$TEXT"
TEXT_SECONDARY="$SUBTLE"
INK="$TEXT_PRIMARY"

# ── Accent roles ──────────────────────────────────────────────
ACCENT_PRIMARY="{palette['IRIS']}"
ACCENT_SECONDARY="{palette['ACCENT_SECONDARY']}"
BORDER_ACCENT="{palette['BORDER_ACCENT']}"

# ── Battery semantic colors ───────────────────────────────────
BATTERY_CRIT="{palette['BATTERY_CRIT']}"
BATTERY_LOW="{palette['BATTERY_LOW']}"
BATTERY_MED="{palette['BATTERY_MED']}"
BATTERY_HIGH="{palette['BATTERY_HIGH']}"
BATTERY_FULL="{palette['BATTERY_FULL']}"

# ── Status roles ──────────────────────────────────────────────
WARN="$GOLD"
ERROR="$LOVE"
SUCCESS="$FOAM"
INFO="$IRIS"

# ── Weather semantic colors (glyph-only usage) ────────────────
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
'''
        palette_sh.write_text(content)
        palette_sh.chmod(0o755)
        print(f"✅ Created {palette_sh}")

    def wallpaper_only(self, target: str):
        """Regenerate wallpaper for an existing theme given a file or directory."""
        target_path = Path(target).expanduser().resolve()

        if target_path.is_dir():
            theme_dir = target_path
            sh_files = list(theme_dir.glob("palette-*.sh"))
            if not sh_files:
                print(f"❌ No palette-*.sh found in {theme_dir}")
                sys.exit(1)
            palette_sh = sh_files[0]
        elif target_path.is_file():
            theme_dir = target_path.parent
            if target_path.suffix == '.sh':
                palette_sh = target_path
            else:
                # Accept .nix path or bare slug — look for matching .sh sibling
                stem = target_path.stem  # e.g. palette-mint-chocolate-chip
                palette_sh = theme_dir / f"{stem}.sh"
                if not palette_sh.exists():
                    sh_files = list(theme_dir.glob("palette-*.sh"))
                    if not sh_files:
                        print(f"❌ No palette-*.sh found in {theme_dir}")
                        sys.exit(1)
                    palette_sh = sh_files[0]
        else:
            # Maybe it's a bare theme name — search under themes/
            themes_root = Path.home() / "nixos" / "themes"
            matches = list(themes_root.rglob(target))
            if not matches:
                print(f"❌ '{target}' is not a valid file, directory, or theme name.")
                sys.exit(1)
            theme_dir = matches[0] if matches[0].is_dir() else matches[0].parent
            sh_files = list(theme_dir.glob("palette-*.sh"))
            if not sh_files:
                print(f"❌ No palette-*.sh found in {theme_dir}")
                sys.exit(1)
            palette_sh = sh_files[0]

        # Slug is the part after "palette-"
        slug = palette_sh.stem[len("palette-"):]

        # Theme identity from directory structure: .../themes/FOLDER/THEME_NAME/
        self.theme_name = theme_dir.name
        self.folder = theme_dir.parent.name

        # Parse colors from the shell palette — simple KEY="#rrggbb" lines
        palette = {}
        for line in palette_sh.read_text().splitlines():
            m = re.match(r'^([A-Z_]+)="(#[0-9a-fA-F]{6})"', line)
            if m:
                palette[m.group(1)] = m.group(2)

        self.primary_color = palette.get('BASE')
        if not self.primary_color:
            print("❌ Could not read BASE color from palette file.")
            sys.exit(1)

        # Older palette files may not have SHADOW — compute it from BASE
        if 'SHADOW' not in palette:
            mode = ColorMath.theme_mode(self.primary_color)
            if mode == "dark":
                palette['SHADOW'] = ColorMath.calc_color(
                    ColorMath.calc_color(self.primary_color, "desaturate", 30), "darken", 8
                )
            else:
                palette['SHADOW'] = ColorMath.calc_color(
                    ColorMath.calc_color(self.primary_color, "desaturate", 35), "darken", 20
                )

        print(f"🖼️  Regenerating wallpaper for '{self.theme_name}' (slug: {slug})...")
        self.generate_wallpaper(palette, slug)

    def generate_wallpaper(self, palette: dict, slug: str):
        """Generate a gradient wallpaper with tinted logo overlay."""
        width, height = 1920, 1080
        base_color = ColorMath.hex_to_rgb(self.primary_color)
        dark_color = ColorMath.hex_to_rgb(palette['SHADOW'])

        wallpaper = Image.new("RGB", (width, height), base_color)
        draw = ImageDraw.Draw(wallpaper)

        for i in range(height):
            r = int(base_color[0] + (dark_color[0] - base_color[0]) * (i / height))
            g = int(base_color[1] + (dark_color[1] - base_color[1]) * (i / height))
            b = int(base_color[2] + (dark_color[2] - base_color[2]) * (i / height))
            draw.line([(0, i), (width, i)], fill=(r, g, b))

        svg_template_path = self.script_dir.parent / "assets" / "lix-wp-template.svg"
        template_path = self.script_dir.parent / "assets" / "lix-wp-template.png"

        if svg_template_path.exists() and _CAIROSVG:
            svg_text = svg_template_path.read_text()
            subs = {
                '{{LOVE}}':      palette.get('LOVE', '#b55690'),
                '{{LOVE_DARK}}': ColorMath.calc_color(palette.get('LOVE', '#b55690'), 'darken', 20),
                '{{ROSE}}':      palette.get('ROSE', '#d162a4'),
            }
            for placeholder, color in subs.items():
                svg_text = svg_text.replace(placeholder, color)
            png_bytes = _cairosvg.svg2png(bytestring=svg_text.encode(), output_height=500)
            logo = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
            lw, lh = logo.size
            logo_pos = ((width - lw) // 2, (height - lh) // 2)
            wallpaper.paste(logo, logo_pos, logo)

        elif template_path.exists():
            logo = Image.open(template_path).convert("RGBA")
            lw, lh = logo.size

            _, _, _, logo_alpha = logo.split()
            luminance = logo.convert("RGB").convert("L")

            # ── Build gradient LUT: luminance value → palette color ────────
            # Anchor to primary_color (BASE) — this IS the flavor color the user
            # chose. IRIS/LOVE/GOLD are semantic palette roles unrelated to the
            # ice cream color, so deriving the LUT from them produces wrong results.
            accent_stops = [
                ColorMath.hex_to_rgb(ColorMath.calc_color(self.primary_color, "darken", 30)),
                ColorMath.hex_to_rgb(ColorMath.calc_color(self.primary_color, "darken", 10)),
                ColorMath.hex_to_rgb(self.primary_color),
                ColorMath.hex_to_rgb(ColorMath.calc_color(self.primary_color, "lighten", 30)),
            ]
            n_segs = len(accent_stops) - 1
            lut_r = bytearray(256)
            lut_g = bytearray(256)
            lut_b = bytearray(256)
            for i in range(256):
                t = i / 255.0
                seg = min(int(t * n_segs), n_segs - 1)
                f = t * n_segs - seg
                c1, c2 = accent_stops[seg], accent_stops[seg + 1]
                lut_r[i] = int(c1[0] + (c2[0] - c1[0]) * f)
                lut_g[i] = int(c1[1] + (c2[1] - c1[1]) * f)
                lut_b[i] = int(c1[2] + (c2[2] - c1[2]) * f)

            # Gradient applied to entire template — ice cream AND letters get
            # theme colors. The cone layer is composited on top of this.
            gradient_rgb = Image.merge("RGB", (
                luminance.point(bytes(lut_r)),
                luminance.point(bytes(lut_g)),
                luminance.point(bytes(lut_b)),
            ))

            # ── Cone: always warm tan, luminance-shaded for natural depth ──
            CONE_TAN = (205, 145, 75)
            boost = 1.5
            cone_rgb = Image.merge("RGB", (
                luminance.point(bytes([min(255, int(CONE_TAN[0] * i / 255 * boost)) for i in range(256)])),
                luminance.point(bytes([min(255, int(CONE_TAN[1] * i / 255 * boost)) for i in range(256)])),
                luminance.point(bytes([min(255, int(CONE_TAN[2] * i / 255 * boost)) for i in range(256)])),
            ))

            # ── Cone mask: prefer explicit asset, fall back to y-split ─────
            # Ideal: assets/lix-cone-mask.png — a white silhouette of just the
            # cup shape (no ice cream, no letters), black elsewhere.
            # Validate: if >50% white the mask is degenerate (covers whole image)
            # and we fall back to the y-split rather than tanning all the ice cream.
            cone_mask_path = self.script_dir.parent / "assets" / "lix-cone-mask.png"
            use_asset = False
            if cone_mask_path.exists():
                candidate = Image.open(cone_mask_path).convert("L").resize((lw, lh), Image.LANCZOS)
                pixels = list(candidate.tobytes())
                white_frac = sum(1 for v in pixels if v > 200) / len(pixels)
                if white_frac < 0.50:
                    cone_mask = candidate
                    use_asset = True
                else:
                    print(f"⚠️  lix-cone-mask.png is {white_frac:.0%} white (degenerate) — using y-split fallback.")
            if not use_asset:
                cone_y = int(lh * 0.62)
                cone_mask = Image.new("L", (lw, lh), 0)
                cone_draw = ImageDraw.Draw(cone_mask)
                cone_draw.rectangle([(0, cone_y), (lw, lh)], fill=255)
                blend_h = 24
                for dy in range(blend_h):
                    v = int(255 * dy / blend_h)
                    cone_draw.line([(0, cone_y - blend_h + dy), (lw, cone_y - blend_h + dy)], fill=v)

            # ── Composite: tan cone over gradient base ─────────────────────
            final_rgb = Image.composite(cone_rgb, gradient_rgb, cone_mask)
            final_logo = final_rgb.convert("RGBA")
            final_logo.putalpha(logo_alpha)

            logo_pos = (
                (width - lw) // 2,
                (height - lh) // 2,
            )
            wallpaper.paste(final_logo, logo_pos, final_logo)
        else:
            print("⚠️  No template found (checked lix-wp-template.svg and .png). Skipping logo overlay.")

        wallpaper_path = Path.home() / f"nixos/themes/{self.folder}/{self.theme_name}/wallpaper-{slug}.png"
        wallpaper.save(wallpaper_path)
        print(f"🖼️  Wallpaper generated: {wallpaper_path}")

    def run_harmonizer(self):
        """Run the harmonizer script if it exists."""
        if self.harmonizer.exists():
            print("🔄 Running Harmonizer to ensure structural consistency...")
            try:
                subprocess.run([str(self.harmonizer)], check=True)
            except subprocess.CalledProcessError as e:
                print(f"⚠️  Harmonizer failed: {e}", file=sys.stderr)
        else:
            print(f"⚠️  Warning: Harmonizer script not found at {self.harmonizer}. Skipping sync.")

    def generate(self):
        """Main generation workflow."""
        # Get inputs
        self.get_inputs_interactive()

        # Validate
        if not self.validate_inputs():
            sys.exit(1)

        # Setup paths
        palette_nix, palette_sh, slug, theme_dir = self.setup_paths()

        print(f"🎨 Generating {self.theme_name} (slug: {slug})...\n")

        # Validate and adjust colors
        mode = ColorMath.theme_mode(self.primary_color)
        self.validate_and_adjust_colors(mode)

        # Calculate palette
        palette = self.calculate_palette(mode)

        # Generate files
        nemo_css_src = theme_dir / "nemo.css"
        self.generate_nix_file(palette, slug, palette_nix)
        self.generate_shell_file(palette, palette_sh)
        self.generate_nemo_css(palette, nemo_css_src)
        self.generate_wofi_css(palette, theme_dir)
        self.generate_fuzzel_ini(palette, theme_dir)
        self.generate_wvkbd_args(palette, theme_dir)
        self.generate_wallpaper(palette, slug)

        # Symlink nemo.css into ~/.config/nemo/
        nemo_cfg_dir = Path.home() / ".config" / "nemo"
        nemo_cfg_dir.mkdir(parents=True, exist_ok=True)
        nemo_css_link = nemo_cfg_dir / "nemo.css"
        if nemo_css_link.is_symlink() or nemo_css_link.exists():
            nemo_css_link.unlink()
        nemo_css_link.symlink_to(nemo_css_src)
        print(f"🔗 Symlinked: {nemo_css_link} → {nemo_css_src}")

        # Final output
        print(f"\n✨ Done! Theme '{self.theme_name}' is ready.")
        print(f"   Location: {Path.home()}/nixos/themes/{self.folder}/{self.theme_name}")
        print(f"   Slug: {slug}")
        print(f"   Mode: {mode}")
        print("\n   Files created:")
        print(f"     - palette-{slug}.nix")
        print(f"     - palette-{slug}.sh")
        print(f"     - nemo.css")
        print(f"     - wofi.css")
        print(f"     - fuzzel.ini")
        print(f"     - wvkbd-colors.sh")
        print(f"     - wallpaper-{slug}.png")
        print("\n   Next steps:")
        print("   1. Review palette file")
        print("   2. Rebuild: nrs")
        print("   3. Activate: set-theme {}".format(slug))


def main():
    parser = argparse.ArgumentParser(description="Generate Lix color themes")
    parser.add_argument("-f", "--folder", default=None, help="Theme folder (default: Lix)")
    parser.add_argument("--theme", default=None, help="Theme name")
    parser.add_argument("--primary", default=None, help="Primary/base color (hex)")
    parser.add_argument("--secondary", default=None, help="Love/secondary color (hex)")
    parser.add_argument("--pine", default=None, help="Pine/green color (hex)")
    parser.add_argument("--accent", default=None, help="Iris/accent color (hex)")
    parser.add_argument("--gold", default=None, help="Gold/warm color (hex)")
    parser.add_argument("--rose", default=None, help="Rose/pink color (hex)")
    parser.add_argument("--foam", default=None, help="Foam/seafoam color (hex)")
    parser.add_argument("-w", "--wallpaper-only", metavar="PATH",
                        help="Regenerate wallpaper for an existing theme (file or directory)")
    parser.add_argument("--colorhunt", metavar="URL",
                        help="Pre-populate colors from a colorhunt.co palette URL")

    args = parser.parse_args()

    initial_cols = None
    if args.colorhunt:
        try:
            ch_colors = parse_colorhunt_url(args.colorhunt)
            print(f"ColorHunt palette: {' '.join(ch_colors)}")
            initial_cols = map_colorhunt_to_slots(ch_colors)
            filled = [s for s in zip(["BASE","LOVE","ROSE","PINE","FOAM","IRIS","GOLD"], initial_cols) if s[1]]
            if filled:
                print(f"Pre-filled slots: {', '.join(f'{n}={c}' for n, c in filled)}")
        except ValueError as e:
            print(f"❌ {e}", file=sys.stderr)
            sys.exit(1)

    generator = ThemeGenerator(
        folder=args.folder,
        theme_name=args.theme,
        primary=args.primary,
        secondary=args.secondary,
        rose=args.rose,
        pine=args.pine,
        foam=args.foam,
        accent=args.accent,
        gold=args.gold,
        initial_cols=initial_cols,
    )

    if args.wallpaper_only:
        generator.wallpaper_only(args.wallpaper_only)
    else:
        generator.generate()


if __name__ == "__main__":
    main()
