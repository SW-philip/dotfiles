# Theme-Gen Color Picker — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expand the TUI color picker to 7 slots, add WCAG contrast dimming + live readout, and promote ROSE/FOAM from derived to direct palette inputs.

**Architecture:** All changes are in `tools/theme-gen.py`. The TUI (`ThemePickerApp` + widgets) gets new slot count, contrast-aware grid rendering, and a live ratio label. `ThemeGenerator` gains `rose`/`foam` attributes; `calculate_palette()` uses them directly instead of deriving them.

**Tech Stack:** Python 3, Textual (TUI), Pillow (wallpaper), colorsys (HSV math)

---

### Task 1: Expand slot constants

**Files:**
- Modify: `tools/theme-gen.py` (lines ~35-40, inside `if _TUI:` block)

**Step 1: Update `_NAMES` and `_DESCS`**

Replace:
```python
_NAMES = ["Base",  "Love",       "Pine",  "Iris",        "Gold"]
_DESCS = ["bg",    "red accent", "green", "blue/purple", "warm/yellow"]
```
With:
```python
_NAMES = ["Base",  "Love",      "Rose",  "Pine",  "Foam",    "Iris",        "Gold"]
_DESCS = ["bg",    "red/warm",  "pink",  "green", "seafoam", "blue/purple", "warm/yellow"]
```

**Step 2: Verify nothing crashes at import**

```bash
python3 -c "import tools.theme_gen" 2>&1 || python3 tools/theme-gen.py --help
```
Expected: help text prints, no traceback.

**Step 3: Commit**
```bash
git add tools/theme-gen.py
git commit -m "feat: expand picker slot constants to 7 (add ROSE, FOAM)"
```

---

### Task 2: Update all `% 5` slot arithmetic to `% 7`

**Files:**
- Modify: `tools/theme-gen.py` — `action_nxt`, `action_prv`, `action_pick`, `_Slots.__init__`, `ThemePickerApp.__init__`

**Step 1: Find every hardcoded `5` in the TUI section**

```bash
grep -n "% 5\|\[None\] \* 5\|range(1, 6)" tools/theme-gen.py
```
Expected lines: `_cols: list = [None] * 5` (×2), `% 5` (×3), `range(1, 6)`.

**Step 2: Update each occurrence**

- `[None] * 5` → `[None] * 7` (two places: `_Slots.__init__` and `ThemePickerApp.__init__`)
- `% 5` → `% 7` (three places: `action_nxt`, `action_prv`, `action_pick`)
- `range(1, 6)` → `range(1, 8)` in `action_pick`

**Step 3: Verify**
```bash
python3 tools/theme-gen.py --help
```
Expected: no crash.

**Step 4: Commit**
```bash
git add tools/theme-gen.py
git commit -m "feat: update slot arithmetic for 7-slot picker"
```

---

### Task 3: Add `base_hex` reactive to `_ColorGrid`, wire contrast dimming

**Files:**
- Modify: `tools/theme-gen.py` — `_ColorGrid` class, `ThemePickerApp._sync()`

**Step 1: Add `base_hex` reactive to `_ColorGrid`**

Inside the `_ColorGrid` class, after the existing reactives:
```python
base_hex: reactive[str] = reactive("")   # set when BASE slot is filled
```

**Step 2: Update `_ColorGrid.render()` to dim low-contrast cells**

The existing render loop iterates `y` (value rows) and `x` (saturation cols). After computing `r, g, b` for each cell, add contrast dimming:

```python
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
```

**Step 3: Wire `base_hex` from `_sync()` in `ThemePickerApp`**

In `_sync()`, after the existing lines, add:
```python
base = self._cols[0]
self.query_one("#grid", _ColorGrid).base_hex = base if (self._slot > 0 and base) else ""
```

**Step 4: Verify visually (or just no crash)**
```bash
python3 tools/theme-gen.py --help
```

**Step 5: Commit**
```bash
git add tools/theme-gen.py
git commit -m "feat: add contrast dimming to color grid (30% brightness below 3:1 vs BASE)"
```

---

### Task 4: Add live contrast/saturation readout label

**Files:**
- Modify: `tools/theme-gen.py` — `ThemePickerApp.compose()`, `CSS`, `_sync()`

**Step 1: Replace the static `#hint` label with a dynamic `#ratio` label**

In `compose()`, replace:
```python
yield Label("or type hex + Enter", id="hint")
```
With:
```python
yield Label("", id="ratio")
```

**Step 2: Update CSS** — replace `#hint` style (if any) with `#ratio`:
```python
# In CSS string, find any #hint reference and rename to #ratio
# If none exists, add:
"#ratio { color: $text-muted; margin-left: 2; }"
```

**Step 3: Update `_sync()` to populate `#ratio`**

Add this block at the end of `_sync()`:
```python
try:
    grid = self.query_one("#grid", _ColorGrid)
    cur = grid.current_hex()
    if self._slot == 0:
        # BASE slot: show saturation percentage as neutralness guide
        _, s, _ = _hex2hsv(cur)
        label = f"sat {s*100:.0f}%  (lower = more neutral)"
    else:
        base = self._cols[0]
        if base:
            ratio = ColorMath.contrast_ratio(cur, base)
            mark = "✓" if ratio >= 3.0 else "✗"
            label = f"{ratio:.1f}:1 {mark} vs BASE"
        else:
            label = "pick BASE first"
    self.query_one("#ratio", Label).update(label)
except Exception:
    pass
```

**Step 4: Test**
```bash
python3 tools/theme-gen.py --help
```

**Step 5: Commit**
```bash
git add tools/theme-gen.py
git commit -m "feat: add live contrast ratio / saturation readout to picker"
```

---

### Task 5: Add BASE-duplicate guard in `action_pick()`

**Files:**
- Modify: `tools/theme-gen.py` — `ThemePickerApp.action_pick()`

**Step 1: Update `action_pick()` to block near-duplicate picks**

Replace the existing `action_pick`:
```python
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
```

**Step 2: Also apply the same guard in `on_input_submitted()` (hex entry)**

After the hex validation line, before assigning `self._cols[self._slot]`:
```python
if self._slot > 0 and self._cols[0]:
    ratio = ColorMath.contrast_ratio(val.lower(), self._cols[0])
    if ratio < 1.5:
        self.notify("Too similar to BASE — needs more contrast", severity="warning")
        event.input.value = ""
        return
```

**Step 3: Commit**
```bash
git add tools/theme-gen.py
git commit -m "feat: block accent picks that duplicate BASE (contrast < 1.5:1)"
```

---

### Task 6: Update `action_gen()` result dict for 7 slots

**Files:**
- Modify: `tools/theme-gen.py` — `ThemePickerApp.action_gen()`

**Step 1: Replace the result dict**

Current:
```python
self.result = dict(
    theme_name=name,
    primary=self._cols[0],
    secondary=self._cols[1],
    pine=self._cols[2],
    accent=self._cols[3],
    gold=self._cols[4],
)
```

Replace with:
```python
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
```

**Step 2: Commit**
```bash
git add tools/theme-gen.py
git commit -m "feat: include rose and foam in TUI result dict"
```

---

### Task 7: Add `rose`/`foam` to `ThemeGenerator` and promote in `calculate_palette()`

**Files:**
- Modify: `tools/theme-gen.py` — `ThemeGenerator.__init__()`, `get_inputs_interactive()`, `calculate_palette()`

**Step 1: Write a test for the palette promotion**

Create `tools/test_theme_gen.py`:
```python
import sys; sys.path.insert(0, '.')
# Patch PIL to avoid import errors in headless env
import unittest
from unittest.mock import MagicMock
sys.modules['PIL'] = MagicMock()
sys.modules['PIL.Image'] = MagicMock()
sys.modules['PIL.ImageDraw'] = MagicMock()
sys.modules['PIL.ImageChops'] = MagicMock()

from tools.theme_gen import ThemeGenerator  # adjust import as needed

class TestPalettePromotion(unittest.TestCase):
    def _make_gen(self, rose="#ff69b4", foam="#40e0d0"):
        g = ThemeGenerator(
            primary="#1a1a2e", secondary="#e94560", rose=rose,
            pine="#0f3460", foam=foam, accent="#533483", gold="#e2b96f"
        )
        return g

    def test_rose_is_direct(self):
        g = self._make_gen(rose="#ff69b4")
        mode = g.calculate_palette.__func__  # get method
        # Call calculate_palette and check ROSE == input
        from tools.theme_gen import ColorMath
        g.primary_color = "#1a1a2e"
        g.secondary_color = "#e94560"
        g.pine_color = "#0f3460"
        g.accent_color = "#533483"
        g.gold_color = "#e2b96f"
        palette = g.calculate_palette("dark")
        self.assertEqual(palette['ROSE'], "#ff69b4")

    def test_foam_is_direct(self):
        g = self._make_gen(foam="#40e0d0")
        palette = g.calculate_palette("dark")
        self.assertEqual(palette['FOAM'], "#40e0d0")

if __name__ == "__main__":
    unittest.main()
```

**Step 2: Run test — expect FAIL**
```bash
python3 tools/test_theme_gen.py 2>&1
```
Expected: ImportError or AttributeError (rose/foam not on ThemeGenerator yet).

**Step 3: Add `rose` and `foam` to `ThemeGenerator.__init__()`**

```python
def __init__(self, folder=None, theme_name=None,
             primary=None, secondary=None,
             pine=None, accent=None, gold=None,
             rose=None, foam=None):          # ← add these two
    ...
    self.rose_color = rose
    self.foam_color = foam
```

**Step 4: Update `calculate_palette()` — promote ROSE and FOAM**

Find and replace:
```python
# Old (derived):
palette['ROSE'] = ColorMath.calc_color(self.secondary_color, "shift_hue", -20)
palette['FOAM'] = ColorMath.calc_color(
    ColorMath.calc_color(self.pine_color, "desaturate", 25), "lighten", 8
)
```
With:
```python
# New (direct):
palette['ROSE'] = self.rose_color
palette['FOAM'] = self.foam_color
```

**Step 5: Run test — expect PASS**
```bash
python3 tools/test_theme_gen.py -v
```
Expected: both tests pass.

**Step 6: Update `get_inputs_interactive()` prompts**

Add prompts for ROSE and FOAM after LOVE:
```python
if not self.rose_color:
    self.rose_color = input("🌸 Enter Rose / Pink Color (Hex): ").strip()
# ... (after pine prompt) ...
if not self.foam_color:
    self.foam_color = input("🌊 Enter Foam / Seafoam Color (Hex): ").strip()
```

Also add ROSE and FOAM to `validate_inputs()` check and to the TUI result consumption block (where `self.primary_color = result['primary']` etc.):
```python
self.rose_color  = result['rose']
self.foam_color  = result['foam']
```

**Step 7: Commit**
```bash
git add tools/theme-gen.py tools/test_theme_gen.py
git commit -m "feat: promote ROSE and FOAM to direct ThemeGenerator inputs"
```

---

### Task 8: Update `validate_and_adjust_colors()` for ROSE and FOAM

**Files:**
- Modify: `tools/theme-gen.py` — `validate_and_adjust_colors()`

**Step 1: Add ROSE check (3:1 vs BASE)**

After the existing PINE check block, add:
```python
# Rose vs Primary (3.0:1)
rose_ratio = ColorMath.contrast_ratio(self.rose_color, self.primary_color)
print(f"   Rose vs Primary:      {rose_ratio:.2f}:1  (target ≥3.0)")
if rose_ratio < 3.0:
    print("   ⚡ Boosting rose to meet 3.0:1...")
    self.rose_color = self.auto_boost(
        self.rose_color, self.primary_color, 3.0, boost_dir
    )
    print(f"   → {self.rose_color}  ({ColorMath.contrast_ratio(self.rose_color, self.primary_color):.2f}:1)")
```

**Step 2: Add FOAM check (3:1 vs BASE)**

After ROSE check:
```python
# Foam vs Primary (3.0:1)
foam_ratio = ColorMath.contrast_ratio(self.foam_color, self.primary_color)
print(f"   Foam vs Primary:      {foam_ratio:.2f}:1  (target ≥3.0)")
if foam_ratio < 3.0:
    print("   ⚡ Boosting foam to meet 3.0:1...")
    self.foam_color = self.auto_boost(
        self.foam_color, self.primary_color, 3.0, boost_dir
    )
    print(f"   → {self.foam_color}  ({ColorMath.contrast_ratio(self.foam_color, self.primary_color):.2f}:1)")
```

**Step 3: Commit**
```bash
git add tools/theme-gen.py
git commit -m "feat: validate ROSE and FOAM contrast in validate_and_adjust_colors"
```

---

### Task 9: Add `--rose` and `--foam` CLI args

**Files:**
- Modify: `tools/theme-gen.py` — `main()` argparse block and `ThemeGenerator(...)` construction

**Step 1: Add args**

```python
parser.add_argument("--rose",  default=None, help="Rose/pink color (hex)")
parser.add_argument("--foam",  default=None, help="Foam/seafoam color (hex)")
```

**Step 2: Pass to ThemeGenerator**

```python
generator = ThemeGenerator(
    ...
    rose=args.rose,
    foam=args.foam,
)
```

**Step 3: Test CLI**
```bash
python3 tools/theme-gen.py --help | grep -E "rose|foam"
```
Expected: two lines showing `--rose` and `--foam`.

**Step 4: Commit**
```bash
git add tools/theme-gen.py
git commit -m "feat: add --rose and --foam CLI args to theme-gen"
```

---

### Task 10: Update shell palette template to write ROSE/FOAM as direct values

**Files:**
- Modify: `tools/theme-gen.py` — `generate_shell_file()` template string

**Step 1: Confirm current ROSE/FOAM lines in template**

Search for `ROSE=` and `FOAM=` in the f-string inside `generate_shell_file()`.

**Step 2: Ensure they use `palette['ROSE']` and `palette['FOAM']` directly**

They should already reference palette dict values — confirm they do NOT call `calc_color` inline. Since `calculate_palette()` now sets them directly, the template just needs:
```python
ROSE="{palette['ROSE']}"
FOAM="{palette['FOAM']}"
```
This should already be the case; verify and fix if not.

**Step 3: Integration smoke test**

```bash
python3 tools/theme-gen.py \
  --theme TestTheme \
  --primary "#1a1a2e" \
  --secondary "#e94560" \
  --rose "#ff69b4" \
  --pine "#0f3460" \
  --foam "#40e0d0" \
  --accent "#533483" \
  --gold "#e2b96f" 2>&1 | head -20
```
Expected: palette generation output, no crash. Check `themes/Lix/TestTheme/palette-test-theme.sh` exists.

```bash
grep "ROSE\|FOAM" themes/Lix/TestTheme/palette-test-theme.sh
```
Expected:
```
ROSE="#ff69b4"
FOAM="#40e0d0"
```

**Step 4: Clean up test theme**
```bash
rm -rf themes/Lix/TestTheme
```

**Step 5: Commit**
```bash
git add tools/theme-gen.py
git commit -m "feat: complete 7-slot theme-gen picker with ROSE/FOAM as direct inputs"
```

---

### Task 11: Final cleanup — remove derived-only ROSE/FOAM fallback logic if any remains

**Files:**
- Modify: `tools/theme-gen.py`

**Step 1: Search for any remaining derivation of ROSE/FOAM**
```bash
grep -n "shift_hue.*-20\|ROSE.*calc_color\|FOAM.*calc_color\|desaturate.*25.*lighten.*8" tools/theme-gen.py
```
Expected: no matches. If any remain, remove them.

**Step 2: Run full test suite**
```bash
python3 tools/test_theme_gen.py -v
```
Expected: all pass.

**Step 3: Final commit**
```bash
git add tools/theme-gen.py
git commit -m "chore: remove leftover ROSE/FOAM derivation logic"
```
