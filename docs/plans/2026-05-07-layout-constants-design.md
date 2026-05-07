# Layout Constants — Design

**Date:** 2026-05-07
**Goal:** Single source of truth for all spacing, radius, and shadow constants across the OS UI stack (Niri, Waybar, Wofi, Wleave, Nemo, Fuzzel). Every surface that renders borders, gaps, or shadows reads from one place.

---

## Problem

Layout values are scattered as magic numbers across five files with no shared reference:

| Surface | Value | File |
|---------|-------|------|
| Niri gaps | `6` | `home/niri/config.kdl.nix` |
| Niri border width | `2` | `home/niri/config.kdl.nix` |
| Waybar module radius | `8px` | `scripts/auto-theme.py` (template) |
| Waybar pill group radius | `12px` | `scripts/auto-theme.py` (template) |
| Waybar workspace button radius | `6px` | `scripts/auto-theme.py` (template) |
| Wofi entry radius | `6px` | `scripts/auto-theme.py` (template) |
| Wleave button radius | `12px` | `scripts/auto-theme.py` (template) |
| Fuzzel window radius | `6` | `home/niri/fuzzel.ini` |

Shadow corners are also broken: the hard `0 0 0 1px` outline shadow bleeds past rounded corners at tight spread values, giving modules a squared-off shadow silhouette that fights the rounded border.

---

## Constants

```
RADIUS_SM     = 6     # workspace pills, scrollbars, small controls, fuzzel
RADIUS_MD     = 8     # individual bar modules, entry fields
RADIUS_LG     = 12    # pill groups (toggles, connectivity), wleave buttons
GAP           = 6     # niri layout gap between windows
BORDER_W      = 2     # niri window border width
SHADOW_BLUR   = 10    # drop shadow blur radius (tuned to match RADIUS_MD)
SHADOW_SPREAD = -1    # negative spread pulls shadow inside rounded silhouette
```

Derived (no separate constant needed):
- Inner pill children: `RADIUS_LG - 2 = 10px` (already correct in template)
- Tooltip radius: `RADIUS_MD = 8px`

---

## Architecture

### Nix side — `themes/layout.nix`

New file returning a flat attrset. Imported in the one place that generates the niri config and passed alongside the palette.

```nix
# themes/layout.nix
{
  gap       = 6;
  borderW   = 2;
  radiusSm  = 6;
  radiusMd  = 8;
  radiusLg  = 12;
  shadowBlur   = 10;
  shadowSpread = -1;
}
```

### Niri config — `home/niri/config.kdl.nix`

Signature changes from `{ p, barHeight ? 45 }` to `{ p, l, barHeight ? 45 }`.

Substitutions:
- `gaps 6` → `gaps ${toString l.gap}`
- `width 2` (border) → `width ${toString l.borderW}`

### Python side — `scripts/auto-theme.py`

`LAYOUT` dict at top of file, values matching `layout.nix`:

```python
LAYOUT = {
    "RADIUS_SM":     6,
    "RADIUS_MD":     8,
    "RADIUS_LG":     12,
    "GAP":           6,
    "BORDER_W":      2,
    "SHADOW_BLUR":   10,
    "SHADOW_SPREAD": -1,
}
```

Injected into the template substitution dict in `generate_waybar_css()` and all `write_*` functions, replacing hardcoded values throughout `_WAYBAR_CSS_TEMPLATE` and the CSS string literals in `write_wofi`, `write_wleave`, `write_nemo`.

### Shadow fix

Current (sharp):
```css
0 0 0 1px rgba(${SHADOW_RGB},${SHADOW_A_OUTER}),
0 4px 10px rgba(${SHADOW_RGB},${SHADOW_A_DROP})
```

After (rounded):
```css
0 0 0 1px rgba(${SHADOW_RGB},${SHADOW_A_OUTER}),
0 4px ${SHADOW_BLUR}px ${SHADOW_SPREAD}px rgba(${SHADOW_RGB},${SHADOW_A_DROP})
```

Applied to every box-shadow rule in `_WAYBAR_CSS_TEMPLATE` that has a drop shadow layer.

### Fuzzel — `home/niri/fuzzel.ini`

Static file, not generated. Update `radius=6` manually — it already matches `RADIUS_SM`, so this is a verification pass only.

---

## Files Changed

| File | Change |
|------|--------|
| `themes/layout.nix` | **new** — source of truth for Nix consumers |
| `home/niri/default.nix` | import `layout.nix`, pass as `l` arg to `config.kdl.nix` |
| `home/niri/config.kdl.nix` | `{ p, l, barHeight }` — use `l.gap`, `l.borderW` |
| `scripts/auto-theme.py` | add `LAYOUT` dict; replace all hardcoded radius/shadow values in templates |
| `home/niri/fuzzel.ini` | verify `radius=6` matches `RADIUS_SM` (likely no change needed) |

---

## Out of Scope

- Color values — not touched here
- Ironbar — being purged, not touched
- `tools/theme-gen.py` — only generates palette files, no CSS layout templates
- Per-theme radius variation — layout constants are theme-independent by design
