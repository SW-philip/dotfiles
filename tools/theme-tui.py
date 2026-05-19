#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["textual", "rich", "requests", "Pillow"]
# ///
"""
theme-tui — unified theme manager.

  Create  → color picker TUI → generate + activate
  Browse  → list registered themes → activate instantly
  Tweak   → select theme → reload colors into picker → regenerate
  Edit    → select theme → interactive palette editor (swatch + hex field per color)
"""

import importlib.util
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Optional

from rich.color import Color as RColor
from rich.style import Style as RStyle
from rich.text import Text as RText
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, VerticalScroll, Vertical
from textual.screen import Screen
from textual.widget import Widget
from textual.widgets import Footer, Header, Input, Label, ListItem, ListView, Static

# ── Sibling module loader ─────────────────────────────────────────────────────

_HERE        = Path(__file__).parent
_SCRIPTS_DIR = _HERE.parent / "scripts"
_THEMES_ROOT = _HERE.parent / "themes"


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod  = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


_auto = _load(_SCRIPTS_DIR / "auto-theme.py", "auto_theme")
_gen  = _load(_HERE        / "theme-gen.py",  "theme_gen")

_derive   = _auto.derive_full_palette
_register = _auto.register_theme
_activate = _auto.activate_theme
_TDIR     = _auto.TEAMS_DIR
_pick     = getattr(_gen, "_tui_pick", None)

# ── Theme discovery ───────────────────────────────────────────────────────────

def _current_slug() -> Optional[str]:
    p = Path.home() / ".local/state/theme"
    return p.read_text().strip() if p.exists() else None


def list_themes() -> list[dict]:
    """All registered themes across Teams/, Lix/, Rose-Pine/, etc."""
    themes = []
    for source_dir in sorted(_THEMES_ROOT.iterdir()):
        if not source_dir.is_dir() or source_dir.suffix == ".nix":
            continue
        for theme_dir in sorted(source_dir.iterdir()):
            if not theme_dir.is_dir():
                continue
            pfiles = sorted(theme_dir.glob("palette-*.sh"))
            if not pfiles:
                continue
            slug = pfiles[0].stem.removeprefix("palette-")
            themes.append({
                "slug":       slug,
                "dir":        theme_dir,
                "source":     source_dir.name,
                "palette_sh": pfiles[0],
            })
    return themes


def _read_cols(palette_sh: Path) -> list[Optional[str]]:
    """Read [BASE, LOVE, ROSE, PINE, FOAM, IRIS, GOLD] from a palette.sh."""
    text = palette_sh.read_text()
    return [
        (lambda m: m.group(1) if m else None)(
            re.search(rf'^(?:export )?{k}="(#[0-9a-fA-F]{{6}})"', text, re.MULTILINE)
        )
        for k in ("BASE", "LOVE", "ROSE", "PINE", "FOAM", "IRIS", "GOLD")
    ]

# ── Palette editor helpers ────────────────────────────────────────────────────

_HEX_RE = re.compile(r'^#[0-9a-fA-F]{6}$')


def _mk_swatch(hex_val: str) -> RText:
    h = hex_val.lstrip("#")
    st = RStyle(bgcolor=RColor.from_rgb(int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)))
    return RText("     ", style=st)


def _parse_palette(path: Path) -> list[tuple[str, str]]:
    """Return [(KEY, value), ...] for every export line."""
    entries = []
    for line in path.read_text().splitlines():
        m = re.match(r'^export (\w+)="([^"]*)"', line)
        if m:
            entries.append((m.group(1), m.group(2)))
    return entries


def _write_palette(path: Path, updated: dict[str, str]) -> None:
    """Overwrite only the changed values; preserve comments and structure."""
    text = path.read_text()
    for key, val in updated.items():
        text = re.sub(
            rf'^(export {key}=)"[^"]*"',
            rf'\1"{val}"',
            text,
            flags=re.MULTILINE,
        )
    path.write_text(text)

# ── Action runners ────────────────────────────────────────────────────────────

def _generate(result: dict) -> None:
    """Derive full palette from picker result, register and activate."""
    p = _derive({
        "BASE": result["primary"],
        "LOVE": result["secondary"],
        "ROSE": result["rose"],
        "PINE": result["pine"],
        "FOAM": result["foam"],
    })
    p["IRIS"] = result["accent"]
    p["GOLD"] = result["gold"]
    slug, _ = _register(result["theme_name"], p, "manual")
    _activate(slug, _TDIR / slug)
    print(f"\n✨  {slug} active.")


def _do_activate(t: dict) -> None:
    _activate(t["slug"], t["dir"])
    print(f"✨  {t['slug']} active.")


def _do_edit(t: dict) -> None:
    app = PaletteEditorApp(t["palette_sh"])
    app.run()
    if app.saved:
        _activate(t["slug"], t["dir"])
        print(f"✨  {t['slug']} re-activated.")


def _do_tweak(t: dict) -> None:
    result = _pick(name0=t["slug"], initial_cols=_read_cols(t["palette_sh"]))
    if result:
        _generate(result)

# ── Palette editor TUI ────────────────────────────────────────────────────────

class ColorRow(Widget):
    """One palette entry: KEY  [swatch]  hex-input  (or plain input for non-hex)."""

    DEFAULT_CSS = """
    ColorRow {
        layout: horizontal;
        height: 3;
        margin: 0;
    }
    ColorRow .cr-key {
        width: 26;
        padding: 1 0 1 2;
        color: $text-muted;
        content-align: left middle;
    }
    ColorRow .cr-swatch {
        width: 7;
        content-align: center middle;
    }
    ColorRow .cr-input {
        width: 16;
    }
    ColorRow .cr-plain {
        width: 40;
    }
    """

    def __init__(self, key: str, value: str) -> None:
        super().__init__(id=f"row-{key}")
        self.key_name      = key
        self.current_value = value
        self._is_hex       = bool(_HEX_RE.match(value))

    def compose(self) -> ComposeResult:
        yield Label(f" {self.key_name}", classes="cr-key")
        if self._is_hex:
            yield Static(_mk_swatch(self.current_value), id=f"sw-{self.key_name}", classes="cr-swatch")
            yield Input(
                value=self.current_value,
                id=f"in-{self.key_name}",
                max_length=7,
                classes="cr-input",
            )
        else:
            yield Input(
                value=self.current_value,
                id=f"in-{self.key_name}",
                classes="cr-plain",
            )

    def on_input_changed(self, event: Input.Changed) -> None:
        val = event.value
        self.current_value = val
        if self._is_hex and _HEX_RE.match(val):
            try:
                self.query_one(f"#sw-{self.key_name}", Static).update(_mk_swatch(val))
            except Exception:
                pass


class PaletteEditorApp(App):
    """Interactive palette editor: swatch + hex field per color variable."""

    CSS = """
    Screen { padding: 0; }
    #pal-title { margin: 1 2; color: $text-muted; }
    #pal-scroll { height: 1fr; margin: 0 1 1 1; border: solid $surface; }
    """

    BINDINGS = [
        Binding("ctrl+s", "save",   "Save & activate"),
        Binding("escape", "cancel", "Cancel"),
    ]

    def __init__(self, palette_sh: Path) -> None:
        super().__init__()
        self.palette_sh = palette_sh
        self.saved      = False
        self._entries   = _parse_palette(palette_sh)

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)
        yield Label(
            f"  Editing: {self.palette_sh.name}    [Ctrl+S = save & activate,  Esc = cancel]",
            id="pal-title",
        )
        with VerticalScroll(id="pal-scroll"):
            for key, val in self._entries:
                yield ColorRow(key, val)
        yield Footer()

    def action_save(self) -> None:
        updated = {}
        for key, _ in self._entries:
            try:
                row = self.query_one(f"#row-{key}", ColorRow)
                updated[key] = row.current_value
            except Exception:
                pass
        _write_palette(self.palette_sh, updated)
        self.saved = True
        self.exit()

    def action_cancel(self) -> None:
        self.exit()

# ── Menu TUI ─────────────────────────────────────────────────────────────────

class BrowseScreen(Screen):
    BINDINGS = [
        Binding("escape", "go_back", "Back"),
        Binding("q",      "go_back", "Back", show=False),
    ]

    def __init__(self, purpose: str, themes: list[dict], current: Optional[str]) -> None:
        super().__init__()
        self._purpose = purpose
        self._themes  = themes
        self._current = current

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)
        yield Label(
            f"  {self._purpose.title()} — select a theme    [Esc = back]",
            id="browse-label",
        )
        items = []
        for i, t in enumerate(self._themes):
            mark  = "●" if t["slug"] == self._current else " "
            label = f"  {mark} [{t['source']:12}]  {t['slug']}"
            items.append(ListItem(Static(label), id=f"t{i}"))
        yield ListView(*items, id="browse-list")
        yield Footer()

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        idx = int(event.item.id[1:])
        self.app.selected_theme = self._themes[idx]
        self.app.action = self._purpose
        self.app.exit()

    def action_go_back(self) -> None:
        self.app.pop_screen()


class MainMenuScreen(Screen):
    BINDINGS = [Binding("q", "quit_app", "Quit")]

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)
        with Vertical(id="menu-wrap"):
            yield Label("  Theme Manager", id="menu-title")
            yield ListView(
                ListItem(Static("  Create new theme"),         id="create"),
                ListItem(Static("  Browse & activate"),        id="activate"),
                ListItem(Static("  Tweak existing theme"),     id="tweak"),
                ListItem(Static("  Edit palette colors"),      id="edit"),
                id="menu-list",
            )
        yield Footer()

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        action = event.item.id
        if action == "create":
            self.app.action = "create"
            self.app.exit()
        else:
            self.app.push_screen(
                BrowseScreen(action, self.app._themes, self.app._current)
            )

    def action_quit_app(self) -> None:
        self.app.exit()


class ThemeTUI(App):
    CSS = """
    Screen { padding: 0; }
    #menu-wrap { margin: 3 6; width: 56; }
    #menu-title { margin-bottom: 1; color: $text-muted; text-style: bold; }
    #browse-label { margin: 1 2; color: $text-muted; }
    ListView { height: auto; max-height: 30; border: solid $surface; }
    ListItem { padding: 0 1; }
    """

    def __init__(self) -> None:
        super().__init__()
        self.action: Optional[str] = None
        self.selected_theme: Optional[dict] = None
        self._themes  = list_themes()
        self._current = _current_slug()

    def on_mount(self) -> None:
        self.push_screen(MainMenuScreen())

# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    tui = ThemeTUI()
    tui.run()

    match tui.action:
        case "create":
            if _pick:
                result = _pick()
                if result:
                    _generate(result)
        case "activate":
            if tui.selected_theme:
                _do_activate(tui.selected_theme)
        case "tweak":
            if tui.selected_theme and _pick:
                _do_tweak(tui.selected_theme)
        case "edit":
            if tui.selected_theme:
                _do_edit(tui.selected_theme)


if __name__ == "__main__":
    main()
