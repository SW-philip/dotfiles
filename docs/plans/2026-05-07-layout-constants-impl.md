# Layout Constants — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace all scattered spacing/radius/shadow magic numbers with a single `themes/layout.nix` source of truth, consumed by every CSS and config surface.

**Architecture:** `themes/layout.nix` is a flat Nix attrset. `home/niri/default.nix` imports it as `l` (available to all inline `mk*` functions via closure). `config.kdl.nix` and `home/waybar/style.nix` receive `l` as an explicit arg. `scripts/auto-theme.py` mirrors the same values in a `LAYOUT` dict and injects them into all CSS template strings. The Nix path is used at `nrs` time; the Python path is used when `auto-theme.py` activates a theme at runtime.

**Tech Stack:** Nix (home-manager module), Python 3, CSS

---

### Task 1: Create `themes/layout.nix`

**Files:**
- Create: `themes/layout.nix`

**Step 1: Write the file**

```nix
# themes/layout.nix — layout constants shared across all UI surfaces
# Import as `l` in default.nix; pass as `l` arg to config.kdl.nix and style.nix.
{
  gap         = 6;    # niri window gap
  borderW     = 2;    # niri window border width
  radiusSm    = 6;    # small: workspace pills, scrollbars, fuzzel
  radiusMd    = 8;    # medium: bar modules, entry fields, tooltips
  radiusLg    = 12;   # large: pill groups, wleave buttons
  shadowBlur  = 10;   # drop shadow blur (tuned to radiusMd)
  shadowSpread = -1;  # negative spread pulls shadow inside rounded corners
}
```

**Step 2: Verify it evaluates**

```bash
nix eval --impure --expr 'import ./themes/layout.nix'
```
Expected: `{ borderW = 2; gap = 6; radiusLg = 12; radiusMd = 8; radiusSm = 6; shadowBlur = 10; shadowSpread = -1; }`

**Step 3: Commit**

```bash
git add themes/layout.nix
git commit -m "feat: add themes/layout.nix — layout constants source of truth"
```

---

### Task 2: Update `home/niri/config.kdl.nix`

**Files:**
- Modify: `home/niri/config.kdl.nix` line 4 (signature) and lines 63, 66

**Step 1: Update signature and inject gap/borderW**

Change line 4 from:
```nix
{ p, barHeight ? 45 }: ''
```
To:
```nix
{ p, l, barHeight ? 45 }: ''
```

Change line 63 from:
```
    gaps 6
```
To:
```
    gaps ${toString l.gap}
```

Change line 66 from:
```
        width 2
```
To:
```
        width ${toString l.borderW}
```

**Step 2: Verify it parses (before wiring up the caller)**

```bash
nix eval --impure --expr '
  let p = import ./themes/Rose-Pine/moon/palette-moon.nix;
      l = import ./themes/layout.nix;
  in import ./home/niri/config.kdl.nix { inherit p l; }
' | head -5
```
Expected: starts with `"// home/niri/config.kdl..."` (no error).

**Step 3: Commit**

```bash
git add home/niri/config.kdl.nix
git commit -m "feat(niri): use layout constants for gap and border width"
```

---

### Task 3: Update `home/waybar/style.nix`

This file has the most hardcoded values. Change its signature and replace every radius/shadow constant.

**Files:**
- Modify: `home/waybar/style.nix`

**Step 1: Change signature (line 4)**

From:
```nix
p:
```
To:
```nix
{ p, l }:
```

**Step 2: Replace `.module` border-radius (line 31)**

From: `border-radius: 8px;`
To: `border-radius: ${toString l.radiusMd}px;`

**Step 3: Fix `.module` drop shadow (line 39)**

From: `    0 4px 10px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});`
To: `    0 4px ${toString l.shadowBlur}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});`

**Step 4: Fix `.module:hover` drop shadow (line 57)**

From: `    0 5px 12px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER});`
To: `    0 5px ${toString (l.shadowBlur + 2)}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER});`

**Step 5: Fix pill group `border-radius` (lines 280, 348, 379, 410, 441)**

There are 5 pill group selectors (`#toggles`, `#connectivity`, `#actions`, `#system-stats`, `#storage`) each with `border-radius: 12px;`.

Replace each: `border-radius: 12px;` → `border-radius: ${toString l.radiusLg}px;`

**Step 6: Fix inner pill child `border-radius` (lines 312, 325)**

These are `border-radius: 10px;` — they are `radiusLg - 2` so the inner border stays visually inset.

Replace each: `border-radius: 10px;` → `border-radius: ${toString (l.radiusLg - 2)}px;`

**Step 7: Fix workspace button `border-radius` (line 474)**

From: `border-radius: 6px;`
To: `border-radius: ${toString l.radiusSm}px;`

**Step 8: Fix tooltip `border-radius` (lines 506, 512)**

Both `border-radius: 8px;` in the tooltip rules:
→ `border-radius: ${toString l.radiusMd}px;`

**Step 9: Fix pill group drop shadows (lines 289, 357, 388, 419, 450 — the `0 4px 10px` layers)**

Each: `0 4px 10px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});`
→ `0 4px ${toString l.shadowBlur}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});`

And hover shadow lines 300-301, 368-369, 399-400, 430-431, 461-462:
`0 4px 14px` / `0 5px 12px` pattern:
```
    0 4px 14px rgba(${p.BORDER_ACCENT_RGB},0.20),
    0 5px 12px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER});
```
→
```
    0 4px ${toString (l.shadowBlur + 4)}px ${toString l.shadowSpread}px rgba(${p.BORDER_ACCENT_RGB},0.20),
    0 5px ${toString (l.shadowBlur + 2)}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER});
```

**Step 10: Fix the tooltip drop shadow (line 516)**

From: `    0 4px 12px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});`
To: `    0 4px ${toString l.shadowBlur}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});`

**Step 11: Verify it parses**

```bash
nix eval --impure --expr '
  let p = import ./themes/Rose-Pine/moon/palette-moon.nix;
      l = import ./themes/layout.nix;
  in import ./home/waybar/style.nix { inherit p l; }
' | head -5
```
Expected: starts with `"/* ====..."` (no error).

**Step 12: Commit**

```bash
git add home/waybar/style.nix
git commit -m "feat(waybar): use layout constants for radius and shadow spread"
```

---

### Task 4: Wire `l` into `home/niri/default.nix`

All the inline `mk*` CSS functions close over the `let` block, so adding `l` there makes it available to them without signature changes. Only the two external-file calls need updating.

**Files:**
- Modify: `home/niri/default.nix`

**Step 1: Import layout in the `let` block**

After line 14 (`themesRoot = ../../themes;`), add:
```nix
  l = import "${themesRoot}/layout.nix";
```

**Step 2: Update the `config.kdl.nix` call (line 118)**

From:
```nix
      niriKdl    = pkgs.writeText "niri-config-${slug}.kdl"   (import ./config.kdl.nix { p = t.palette; });
```
To:
```nix
      niriKdl    = pkgs.writeText "niri-config-${slug}.kdl"   (import ./config.kdl.nix { p = t.palette; inherit l; });
```

**Step 3: Update the `style.nix` call (line 120)**

From:
```nix
      waybarCss  = pkgs.writeText "waybar-style-${slug}.css"  (import ../waybar/style.nix t.palette);
```
To:
```nix
      waybarCss  = pkgs.writeText "waybar-style-${slug}.css"  (import ../waybar/style.nix { p = t.palette; inherit l; });
```

**Step 4: Update `mkMakoConfig` border-radius (line 73)**

From: `border-radius=7`
To: `border-radius=${toString (l.radiusSm + 1)}`

(Mako uses unitless integers, not `px`. `radiusSm + 1 = 7` matches current value — confirm this is intentional.)

**Step 5: Update `mkWofiCss` border-radius (line 233)**

From: `border-radius: 6px;`
To: `border-radius: ${toString l.radiusSm}px;`

**Step 6: Update `mkWleaveCSS` border-radius (line 274)**

From: `border-radius: 12px;`
To: `border-radius: ${toString l.radiusLg}px;`

**Step 7: Update both occurrences of wleave `border-radius: 12px` in the `setTheme` inline heredoc (lines 408–411)**

This is the runtime shell heredoc inside the `setTheme` script. It's a bash heredoc — variables expand differently. Change:
```bash
border-radius: 12px;
```
to a literal substituted at build time via the Nix string:
```nix
border-radius: ${toString l.radiusLg}px;
```
(This is inside a Nix string so `${...}` is Nix interpolation, not shell.)

**Step 8: Update `mkFuzzelIni` radius (line 331)**

From: `radius=6`
To: `radius=${toString l.radiusSm}`

**Step 9: Verify Nix evaluates cleanly**

```bash
nix eval --impure --expr '
  (builtins.getFlake "path:.").homeConfigurations
' 2>&1 | head -20
```
Expected: attrset of home configs, no error.

Or faster:
```bash
nix eval --impure --expr 'import ./home/niri/default.nix' 2>&1 | head -5
```

**Step 10: Full rebuild test**

```bash
nrs
```
Expected: rebuild succeeds, niri config and waybar CSS apply cleanly.

**Step 11: Commit**

```bash
git add home/niri/default.nix
git commit -m "feat(niri): wire layout constants into all mk* config generators"
```

---

### Task 5: Update `scripts/auto-theme.py` (Python runtime path)

The Python script activates themes at runtime, bypassing the Nix rebuild. It has its own CSS templates that must stay in sync with the Nix templates.

**Files:**
- Modify: `scripts/auto-theme.py`

**Step 1: Add `LAYOUT` dict after the path constants block (after line ~48)**

```python
# ── Layout constants (mirror of themes/layout.nix) ───────────────────────────
LAYOUT = {
    "RADIUS_SM":      6,
    "RADIUS_MD":      8,
    "RADIUS_LG":      12,
    "GAP":            6,
    "BORDER_W":       2,
    "SHADOW_BLUR":    10,
    "SHADOW_SPREAD":  -1,
}
```

**Step 2: Replace hardcoded values in `_WAYBAR_CSS_TEMPLATE`**

In the template string (lines ~53–465), replace:

| Old | New |
|-----|-----|
| `border-radius: 8px;` (`.module`) | `border-radius: ${RADIUS_MD}px;` |
| `border-radius: 12px;` (pill groups) | `border-radius: ${RADIUS_LG}px;` |
| `border-radius: 10px;` (inner children) | `border-radius: ${RADIUS_LG - 2}px;` |
| `border-radius: 6px;` (workspaces) | `border-radius: ${RADIUS_SM}px;` |
| `0 4px 10px rgba(${SHADOW_RGB}` | `0 4px ${SHADOW_BLUR}px ${SHADOW_SPREAD}px rgba(${SHADOW_RGB}` |
| `0 5px 12px rgba(${SHADOW_RGB}` | `0 5px ${SHADOW_BLUR_HOVER}px ${SHADOW_SPREAD}px rgba(${SHADOW_RGB}` |

Note: `_WAYBAR_CSS_TEMPLATE` uses `string.Template` `${KEY}` syntax — these replacements use Python's format at template construction time, NOT Template substitution. Compute the values and bake them in when defining `_WAYBAR_CSS_TEMPLATE`, like:

```python
_RM  = LAYOUT["RADIUS_MD"]
_RL  = LAYOUT["RADIUS_LG"]
_RS  = LAYOUT["RADIUS_SM"]
_SB  = LAYOUT["SHADOW_BLUR"]
_SP  = LAYOUT["SHADOW_SPREAD"]

_WAYBAR_CSS_TEMPLATE = f"""\
...
  border-radius: {_RM}px;
...
  0 4px {_SB}px {_SP}px rgba(${{SHADOW_RGB}},${{SHADOW_A_DROP}});
...
"""
```

**Important:** `string.Template` uses `${KEY}` for palette substitution. Inside an f-string, those need to be `${{KEY}}` to survive the f-string pass. Or: define the layout values at the top and use Python `.replace()` before constructing the Template. The f-string approach is cleaner — escape all existing `${...}` palette vars as `${{...}}`.

**Step 3: Update `write_wofi`**

In `write_wofi` (line ~1211), replace:
```python
border-radius: 6px;
```
with:
```python
border-radius: {LAYOUT['RADIUS_SM']}px;
```

**Step 4: Update `write_wleave` (second definition, line ~1251)**

Replace:
```python
border-radius: 12px;
```
with:
```python
border-radius: {LAYOUT['RADIUS_LG']}px;
```

**Step 5: Update `write_nemo`**

`border-radius: 4px` in nemo is intentionally small (file icon hover). Leave it as-is — it's not a structural radius.

**Step 6: Smoke test**

```bash
cd /home/prepko/nixos
python3 scripts/auto-theme.py --rose-pine --register-only 2>&1 | tail -5
grep "border-radius" themes/Teams/rose-pine-official/waybar-style.css | head -5
```
Expected: `border-radius: 8px;`, `border-radius: 12px;`, `border-radius: 6px;` — matching the LAYOUT values.

Also verify shadow spread appears:
```bash
grep "shadowSpread\|${-1}px\| -1px" themes/Teams/rose-pine-official/waybar-style.css | head -3
```
Expected: lines containing `-1px` in the drop shadow definitions.

**Step 7: Commit**

```bash
git add scripts/auto-theme.py
git commit -m "feat(auto-theme): use LAYOUT constants for radius and shadow in CSS templates"
```

---

### Task 6: Final verification

**Step 1: Check all radius values are gone from source files**

```bash
grep -rn "border-radius: [0-9]\+px" \
  home/niri/config.kdl.nix \
  home/waybar/style.nix \
  home/niri/default.nix \
  | grep -v "50%" | grep -v "4px"
```
Expected: no output (all structural radii are now interpolated; `50%` for circular elements and `4px` for nemo icon hovers are intentionally kept).

```bash
grep -n "gaps [0-9]\|width [0-9]" home/niri/config.kdl.nix
```
Expected: no output (replaced by `l.*`).

**Step 2: Rebuild**

```bash
nrs
```
Expected: clean build. Niri reloads with correct gaps. Waybar CSS has rounded module shadows.

**Step 3: Visual check**

- Open any floating window: confirm shadow corners match the border-radius curve
- Check waybar module hover states: shadow should look rounded, not square-cornered
- Confirm gaps between windows match the constant (6px)
