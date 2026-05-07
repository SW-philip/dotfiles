# Waybar Theme Picker — Design

**Date:** 2026-05-07
**Status:** Approved

## Summary

Add a right-click fuzzel picker to the existing `custom/mode` Waybar module. Left-click
behavior (cycle Rose-Pine variants) is unchanged. Right-click opens a fuzzel dmenu listing
all themes in `themes/Teams/` with Pango color swatches and friendly names.

## Components

### 1. `home/waybar/scripts/theme-picker.py` (new)

- Enumerates `~/nixos/themes/Teams/` directories
- Reads `palette-{slug}.sh` per theme for `ACCENT_PRIMARY` and `ACCENT_SECONDARY`
- Cross-references `scripts/teamcolors-full.json` for friendly name + league tag
- Custom/API themes not in teamcolors-full.json fall back to title-cased slug
- Formats each line with Pango: `<span foreground="{ACCENT_PRIMARY}">██</span><span foreground="{ACCENT_SECONDARY}">██</span>  Name  [LEAGUE]`
- Pipes to `fuzzel --dmenu --markup --prompt " theme: "`
- Parses selection back to slug, calls `set-team-theme.py "{slug}"`
- No new activation path — delegates entirely to `set-team-theme.py`, which handles
  palette.sh copy → swaybg restart → SIGUSR2 last (safe from waybar on-right-click)

### 2. `home/waybar/default.nix` (modified)

**`chooseModeExec` update:**
- If `~/.local/state/theme` is one of `main|moon|dawn|lilac-juniper` → existing
  `main → moon → dawn → lilac·juniper` tooltip with active one bolded
- Otherwise → tooltip shows the active slug as-is (e.g. `philadelphia-eagles`)
- Icon stays `󰔎` in both cases

**`custom/mode` module update:**
- Add `on-right-click` pointing to `theme-picker.py` via nix path interpolation
  (`${./scripts/theme-picker.py}`)

## Data Flow

```
right-click waybar module
  → theme-picker.py
      → reads ~/nixos/themes/Teams/*/palette-*.sh
      → reads ~/nixos/scripts/teamcolors-full.json
      → fuzzel --dmenu --markup
          ← user selection (display line)
      → extract slug from selection
      → set-team-theme.py "{slug}"
          → copy palette.sh → ~/.config/waybar/palette.sh
          → update ~/.local/state/theme
          → restart swaybg
          → pkill -SIGUSR1 waybar  (hide)
          → sleep 0.3
          → pkill -SIGUSR2 waybar  (reload) ← LAST
```

## Constraints

- SIGUSR2 to waybar must be the final action in any waybar child process (CLAUDE.md)
  — satisfied by delegating to existing `set-team-theme.py`
- No new dependencies — script uses only stdlib (json, pathlib, subprocess)
- Requires one `nrs` after the nix module change to wire up `on-right-click`

## Out of Scope

- Rose-Pine variants in the fuzzel picker (covered by left-click cycling)
- Live preview / color thumbnail images
- Scheduled/automatic theme switching
