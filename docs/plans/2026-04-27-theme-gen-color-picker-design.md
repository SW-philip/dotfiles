# theme-gen.py — Color Picker Redesign

**Date:** 2026-04-27  
**File:** `tools/theme-gen.py`

---

## Goal

Expand the TUI color picker from 5 to 7 direct-input slots, add WCAG contrast feedback to the grid, and block/warn on BASE-duplicate picks.

---

## Slot Structure

7 slots in order: `BASE → LOVE → ROSE → PINE → FOAM → IRIS → GOLD`

ROSE and FOAM change from derived values to direct inputs. Everything else (SURFACE, OVERLAY, HIGHLIGHT_*, SHADOW, WB_*, BATTERY_*, etc.) remains derived from the 7 seeds.

---

## Grid Behavior per Slot

**BASE slot:**
- No contrast dimming (no reference color yet)
- Saturation indicator replaces ratio readout: shows current saturation % so the user can aim for a neutral pick
- No duplicate check (it's the reference)

**Accent slots (LOVE, ROSE, PINE, FOAM, IRIS, GOLD):**
- Grid cells where WCAG contrast vs BASE < 3:1 render at ~30% brightness (dimmed but visible)
- Live contrast readout below grid: `4.2:1 ✓` (≥3:1) or `2.1:1 ✗` (<3:1), updates on every cursor move
- On pick: if picked color's contrast vs BASE < 1.5:1 (essentially a duplicate), show a warning line and do NOT advance to the next slot — user must pick something different

---

## Code Changes

### `_NAMES` / `_DESCS`
```python
_NAMES = ["Base",  "Love",      "Rose",   "Pine",  "Foam",    "Iris",       "Gold"]
_DESCS = ["bg",    "red/warm",  "pink",   "green", "seafoam", "blue/purple","warm/yellow"]
```

### `_cols` list
Grows from 5 → 7 entries throughout `ThemePickerApp`.

### `_Slots` widget
Renders 7 rows instead of 5.

### `ThemePickerApp`
- `_cols: list = [None] * 7`
- `action_pick()`: after picking BASE (slot 0), store it as the contrast reference; for slots 1–6 enforce the duplicate guard
- New helper `_contrast_vs_base()` → calls `ColorMath.contrast_ratio(current_hex, base_hex)`

### `_ColorGrid.render()`
When an accent slot is active and BASE is set:
- For each cell, compute contrast of that cell's color vs BASE
- If < 3:1: render at 30% brightness (`v * 0.3` in HSV before converting to RGB)
- If ≥ 3:1: render normally

### Live readout
Replace the static `#hint` label with a dynamic `#ratio` label that updates on every `_sync()` call, showing the contrast ratio (or saturation % for BASE slot).

### `ThemeGenerator.get_inputs_interactive()`
Accept 7 colors from the TUI result dict, map them to `self.rose_color` and `self.foam_color` new attributes.

### `ThemeGenerator.__init__()`
Add `rose` and `foam` keyword args.

### `calculate_palette()`
- `palette['ROSE'] = self.rose_color` (direct, not derived from LOVE)
- `palette['FOAM'] = self.foam_color` (direct, not derived from PINE)

### `validate_and_adjust_colors()`
Add contrast checks for ROSE and FOAM vs BASE (same 3:1 target as PINE/IRIS/GOLD).

### CLI (`argparse`)
Add `--rose` and `--foam` flags.

### `wallpaper_only()`
Parse `ROSE` and `FOAM` from palette shell file (they're already written there).

---

## Threshold Summary

| Check | Threshold | Effect |
|-------|-----------|--------|
| Grid dim | < 3:1 vs BASE | Cell renders at 30% brightness |
| Live readout ✓ | ≥ 3:1 vs BASE | Green checkmark |
| Live readout ✗ | < 3:1 vs BASE | Red X |
| Duplicate guard | < 1.5:1 vs BASE | Block pick, show warning |
| validate_and_adjust | < 3:1 (accents), < 4.5:1 (secondary) | Auto-boost on generate |

---

## Out of Scope

- Contrast between accents (accents may share hues freely)
- Reordering slots
- Changing derived-color logic beyond ROSE/FOAM promotion
