# sqlch-popup: Head Unit Detail Pass 2

**Date:** 2026-04-01
**File:** `home/niri/sqlch-popup.py`

---

## Goals

Two parallel passes on the existing GTK4 Pioneer DEH popup:

1. **Functional indicators** — wire MONO/ST/LOUD/MUTE to real system state
2. **Physical detail** — chassis seams, screen surround, badge, scuffs, signal zone texture

---

## Pass 1 — Functional Indicators

### Polling additions (inside existing 1.5s `_poll` cycle)

Add two new queries alongside the existing `daemon_send({"cmd": "status"})`:

**A. Volume/mute state** — call `wpctl get-volume @DEFAULT_AUDIO_SINK@` via subprocess.
- Parse float and `[MUTED]` flag from output
- Store on `NowPlaying` as `_vol_level: float` and `_muted: bool`

**B. BT sink active** — reuse the `pw-dump` + jq logic from `volume.sh`:
- Check for any `bluez_output` node in PipeWire
- Store as `_bt_active: bool`
- Run in a background thread (pw-dump is slow) — update state async, same pattern as art fetching

**C. Bitrate** — already available from `_mpv_metadata()` which is called in the poll cycle.
- Read `audio-bitrate` or `bitrate` key; fall back to library `stream.bitrate` field

---

### Indicator logic

| Indicator | Condition | CSS class |
|---|---|---|
| **ST** | bitrate ≥ 128kbps | `.st-ind.playing` (existing green) |
| **MONO** | bitrate < 128kbps or unknown | `.radio-btn.playing` (plain cyan) |
| **MUTE** | `[MUTED]` in wpctl output | `.mute-ind.playing` (new: dim red) |
| **LOUD** (dim) | volume 65%–100% | `.loud-ind.playing` (existing orange) |
| **LOUD** (overdrive) | volume >100% OR BT active | `.loud-ind.overdrive` (new: brighter orange, wider glow) |

When MUTE is active: ST, LOUD, MONO all go dark (muted overrides everything).

MONO and ST are mutually exclusive — only one lit at a time.

---

### New CSS states needed

```css
/* MUTE lit state */
.radio-btn.mute-ind.playing { color: #e05050; border-color: ...; text-shadow: 0 0 8px #e05050; }

/* LOUD overdrive state */
.radio-btn.loud-ind.overdrive { color: #ffb030; text-shadow: 0 0 14px #ff8800, 0 0 6px #ffb030; border-color: #7a4a10; }
```

MONO gets `lit=True` and `extra_class="mono-ind"` so it can light up (currently `lit=False`).
MUTE gets `lit=True` and `extra_class="mute-ind"`.

---

### Group label in collapsed bar

`CollapsedQuickBar` currently shows `[◀]  [1][2][3][4][5][6]  [▶]`.

Add a `Gtk.Label` with class `.group-label` between the ◀ button and the number buttons.
- Text: current active group name (e.g., `FM1`, `INT1`, `AM1`)
- Updated via a new `set_group(name: str)` method on `CollapsedQuickBar`
- `SqlchPopupWindow._on_group_tab_changed` already fires on group change — call `self._collapsed_bar.set_group(name)` there
- Default text: `ALL` when no group filter active

CSS: small, dim cyan, monospace, slight letter-spacing — looks like a band indicator.

---

## Pass 2 — Physical Detail

### Chassis border / outer bezel

Replace the current single `.popup` border with a layered approach:
- Outer ring: 1px solid `#555` top/left, `#222` bottom/right (highlight/shadow bevel)
- 2px gap (background bleeds through as dark channel)
- Inner ring: 1px solid `#333` top/left, `#111` bottom/right
- Creates a "DIN slot" extruded plastic feel

Implemented as additional `box-shadow` layers on `.popup` — no new widgets needed.

### Seam lines

Three 1px horizontal `Gtk.Separator` widgets with class `.seam` inserted into the outer box:
1. Below the LCD/now-playing zone (above toolbar)
2. Below toolbar (above station list)

CSS: `.seam { background: linear-gradient(to right, transparent, #333 20%, #555 50%, #333 80%, transparent); height: 1px; }`

The existing `.divider` already does one of these — extend its style and add a second.

### Screen surround / LCD recess

On `.now-playing`:
- Add `box-shadow: inset 0 2px 6px rgba(0,0,0,0.8), inset 0 1px 0 rgba(255,255,255,0.06)`
- Top-edge bright highlight (the "glass lip") via border-top tweak

### Manufacturer badge

Small `Gtk.Label(label="SQLCH  ◈  DEH-S")` with class `.mfr-badge`, placed in the top-right of the chassis outer box, above the now-playing panel.
- CSS: 8px monospace, `#333` color, letter-spacing 0.15em — stamped plastic look
- Positioned via `halign=END`, `margin_end=8`, `margin_top=3`

### Screen scuffs

Three near-invisible `linear-gradient` overlays on `.now-playing` using `background-image` stacking:
```css
background-image:
  repeating-linear-gradient(...),  /* existing scanlines */
  linear-gradient(127deg, transparent 30%, rgba(255,255,255,0.025) 31%, transparent 32%),
  linear-gradient(53deg,  transparent 55%, rgba(255,255,255,0.015) 56%, transparent 57%),
  linear-gradient(161deg, transparent 70%, rgba(255,255,255,0.02)  71%, transparent 72%);
```

### Signal zone texture

Behind the 9 signal bars, add a `repeating-linear-gradient` dot-matrix background on the containing box:
```css
background-image: repeating-linear-gradient(
  0deg, transparent, transparent 3px, rgba(0,40,80,0.3) 3px, rgba(0,40,80,0.3) 4px
);
```
Subtle dark-blue horizontal lines — like the PCB behind a real signal meter.

---

## Implementation Order

1. MUTE/MONO widget changes (`lit=True`, new classes)
2. CSS for new indicator states (mute-ind, loud-ind overdrive, mono-ind)
3. `_poll` additions: wpctl subprocess call
4. BT detection background thread
5. Bitrate → MONO/ST logic
6. Group label in collapsed bar
7. Physical detail CSS (chassis, seams, scuffs, badge, signal texture)
8. Manufacturer badge widget
