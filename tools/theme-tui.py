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
  Edit    → select theme → open $EDITOR on palette.sh → re-activate
"""

import importlib.util
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Optional

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Vertical
from textual.screen import Screen
from textual.widgets import Footer, Header, Label, ListItem, ListView, Static

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
_pick     = getattr(_gen, "_tui_pick", None)  # None if textual import failed in theme-gen

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

# ── Action runners (called after TUI exits) ───────────────────────────────────

def _generate(result: dict) -> None:
    """Derive full palette from picker result, register and activate."""
    p = _derive({
        "BASE": result["primary"],
        "LOVE": result["secondary"],
        "ROSE": result["rose"],
        "PINE": result["pine"],
        "FOAM": result["foam"],
    })
    # Honour the user's picked IRIS/GOLD rather than auto-derived values
    p["IRIS"] = result["accent"]
    p["GOLD"] = result["gold"]
    slug, _ = _register(result["theme_name"], p, "manual")
    _activate(slug, _TDIR / slug)
    print(f"\n✨  {slug} active.")


def _do_activate(t: dict) -> None:
    _activate(t["slug"], t["dir"])
    print(f"✨  {t['slug']} active.")


def _do_edit(t: dict) -> None:
    subprocess.run([os.environ.get("EDITOR", "nano"), str(t["palette_sh"])])
    _activate(t["slug"], t["dir"])
    print(f"✨  {t['slug']} re-activated.")


def _do_tweak(t: dict) -> None:
    result = _pick(name0=t["slug"], initial_cols=_read_cols(t["palette_sh"]))
    if result:
        _generate(result)

# ── Textual screens ───────────────────────────────────────────────────────────

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
        idx = int(event.item.id[1:])  # strip leading 't'
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
                ListItem(Static("  Edit palette in $EDITOR"),  id="edit"),
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
