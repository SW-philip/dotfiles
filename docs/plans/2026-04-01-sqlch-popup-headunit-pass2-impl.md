# sqlch-popup Head Unit Pass 2 — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire MONO/ST/LOUD/MUTE indicators to real system state, add group label to collapsed bar, and add two visual detail passes (physical chassis, screen scuffs, badge, seams, signal texture).

**Architecture:** All changes are in `home/niri/sqlch-popup.py`. Functional indicator state is gathered in the existing `_do_poll` background thread (plus a new BT detection thread). Visual changes are pure CSS additions and a handful of new `Gtk.Label`/`Gtk.Separator` widgets.

**Tech Stack:** Python 3, GTK4, GLib, subprocess (wpctl), PipeWire (pw-dump via subprocess)

---

### Task 1: Wire MONO to `_radio_indicators` and add MUTE CSS class

**Files:**
- Modify: `home/niri/sqlch-popup.py` (lines 1485, 1503 for widget construction; ~line 493 for CSS)

**Step 1: Make MONO a lit indicator**

Find line 1485:
```python
sig_area.append(_radio_btn("MONO"))
```
Change to:
```python
self._mono_ind = _radio_btn("MONO", lit=False, extra_class="mono-ind")
sig_area.append(self._mono_ind)
```
Note: `lit=False` keeps it out of `_radio_indicators` (we'll manage it manually since MONO and ST are mutually exclusive).

Also store ST indicator reference. Find line 1486:
```python
sig_area.append(_radio_btn("ST",   lit=True, extra_class="st-ind"))
```
Change to:
```python
self._st_ind = _radio_btn("ST", lit=False, extra_class="st-ind")
sig_area.append(self._st_ind)
```
(Remove `lit=True` — we'll manage it manually alongside MONO.)

Find line 1502-1503:
```python
sig_area.append(_radio_btn("LOUD", lit=True, extra_class="loud-ind"))
sig_area.append(_radio_btn("MUTE"))
```
Change to:
```python
self._loud_ind = _radio_btn("LOUD", lit=False, extra_class="loud-ind")
sig_area.append(self._loud_ind)
self._mute_ind = _radio_btn("MUTE", lit=False, extra_class="mute-ind")
sig_area.append(self._mute_ind)
```

Remove ST and LOUD from `_radio_indicators` entirely — they're now managed individually.

**Step 2: Add CSS for new indicator states**

After the existing `.radio-btn.loud-ind.playing` block (~line 499), add:

```css
/* MUTE lit */
.radio-btn.mute-ind.playing {
  color: #e05555;
  border-color: #4a1515;
  border-top-color: #5a1e1e;
  box-shadow: inset 0 1px 4px rgba(0,0,0,0.5), 0 0 7px rgba(224,85,85,0.15);
  text-shadow: 0 0 8px rgba(224,85,85,0.95), 0 0 14px rgba(224,85,85,0.45);
}
/* LOUD overdrive (>100% or BT active) */
.radio-btn.loud-ind.overdrive {
  color: #ffb030;
  border-color: #6a3a08;
  border-top-color: #7a4a10;
  box-shadow: inset 0 1px 4px rgba(0,0,0,0.4), 0 0 12px rgba(255,140,0,0.35);
  text-shadow: 0 0 6px rgba(255,176,48,1.0), 0 0 18px rgba(255,100,0,0.7), 0 0 28px rgba(255,80,0,0.3);
}
```

**Step 3: Add `update_indicators` method to `NowPlaying`**

Add this method after `_set_eq_playing` (~line 1598):

```python
def update_indicators(self, bitrate: int | None, vol: float, muted: bool, bt_active: bool):
    """Update MONO/ST/LOUD/MUTE indicator lights from system state."""
    # MUTE overrides everything
    if muted:
        self._mute_ind.add_css_class("playing")
        self._mono_ind.remove_css_class("playing")
        self._st_ind.remove_css_class("playing")
        self._loud_ind.remove_css_class("playing")
        self._loud_ind.remove_css_class("overdrive")
        return

    self._mute_ind.remove_css_class("playing")

    # MONO vs ST based on bitrate
    if bitrate is not None and bitrate >= 128:
        self._st_ind.add_css_class("playing")
        self._mono_ind.remove_css_class("playing")
    elif bitrate is not None:
        self._mono_ind.add_css_class("playing")
        self._st_ind.remove_css_class("playing")
    else:
        # Unknown bitrate — leave both dim
        self._mono_ind.remove_css_class("playing")
        self._st_ind.remove_css_class("playing")

    # LOUD: overdrive if BT active or vol > 1.0, dim-lit if vol >= 0.65
    self._loud_ind.remove_css_class("playing")
    self._loud_ind.remove_css_class("overdrive")
    if bt_active or vol > 1.0:
        self._loud_ind.add_css_class("overdrive")
    elif vol >= 0.65:
        self._loud_ind.add_css_class("playing")
```

**Step 4: Verify visually**

Run: `python3 /home/prepko/nixos/home/niri/sqlch-popup.py`
Expected: Popup opens, indicators are dim. MUTE/ST/LOUD will light once poll wiring is done in Task 2.

**Step 5: Commit**

```bash
git add home/niri/sqlch-popup.py
git commit -m "feat(popup): wire MONO/ST/LOUD/MUTE indicator refs and CSS states"
```

---

### Task 2: Poll system volume/mute and bitrate, call `update_indicators`

**Files:**
- Modify: `home/niri/sqlch-popup.py` (~lines 2444–2456 `_do_poll`/`_apply_poll`)

**Step 1: Add volume/mute polling helper**

Add this function near `daemon_send` (~line 922):

```python
def _get_vol_state() -> tuple[float, bool]:
    """Return (volume_float, muted) from wpctl. Falls back to (0.0, False) on error."""
    try:
        r = subprocess.run(
            ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
            capture_output=True, text=True, timeout=1,
        )
        line = r.stdout.strip()
        parts = line.split()
        vol = float(parts[1]) if len(parts) >= 2 else 0.0
        muted = "[MUTED]" in line
        return vol, muted
    except Exception:
        return 0.0, False
```

**Step 2: Add BT detection helper**

Add after `_get_vol_state`:

```python
def _get_bt_active() -> bool:
    """Return True if any bluez_output sink node exists in PipeWire."""
    try:
        r = subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3)
        return "bluez_output" in r.stdout
    except Exception:
        return False
```

**Step 3: Add bitrate extraction helper**

Add after `_get_bt_active`:

```python
def _get_stream_bitrate() -> int | None:
    """Return stream bitrate in kbps from MPV metadata, or None."""
    meta = _mpv_metadata()
    if not meta:
        return None
    for key in ("audio-bitrate", "bitrate", "icy-bitrate"):
        val = meta.get(key)
        if val:
            try:
                # MPV reports in bps; convert to kbps if > 1000
                v = int(float(val))
                return v // 1000 if v > 1000 else v
            except (ValueError, TypeError):
                pass
    return None
```

**Step 4: Thread BT detection separately (it's slow)**

Add instance variable in `SqlchPopupWindow.__init__` after the existing state vars (~line 2235):

```python
self._bt_active: bool = False
```

Add BT polling as a separate low-frequency background refresh. In `SqlchPopupWindow.__init__` after `GLib.timeout_add(POLL_MS, self._poll)`:

```python
self._refresh_bt()
GLib.timeout_add(15_000, self._refresh_bt)  # BT check every 15s

def _refresh_bt(self) -> bool:
    threading.Thread(target=self._do_bt_check, daemon=True).start()
    return True

def _do_bt_check(self):
    active = _get_bt_active()
    GLib.idle_add(self._apply_bt, active)

def _apply_bt(self, active: bool):
    self._bt_active = active
    return False
```

**Step 5: Extend `_do_poll` / `_apply_poll`**

Find `_do_poll` (~line 2448):
```python
def _do_poll(self):
    resp = daemon_send({"cmd": "status"})
    icy  = get_icy_track()
    GLib.idle_add(self._apply_poll, resp, icy)
```

Replace with:
```python
def _do_poll(self):
    resp    = daemon_send({"cmd": "status"})
    icy     = get_icy_track()
    vol, muted = _get_vol_state()
    bitrate = _get_stream_bitrate()
    GLib.idle_add(self._apply_poll, resp, icy, vol, muted, bitrate)
```

Find `_apply_poll` (~line 2453):
```python
def _apply_poll(self, resp, icy):
    self._now_playing.update(resp, icy=icy)
    self._station_list.set_active(self._now_playing.get_current_id())
    return False
```

Replace with:
```python
def _apply_poll(self, resp, icy, vol, muted, bitrate):
    self._now_playing.update(resp, icy=icy)
    self._now_playing.update_indicators(bitrate, vol, muted, self._bt_active)
    self._station_list.set_active(self._now_playing.get_current_id())
    return False
```

**Step 6: Verify visually**

Run: `python3 /home/prepko/nixos/home/niri/sqlch-popup.py`
Expected: ST lights green when a ≥128kbps stream plays, MUTE lights red when sink is muted (`wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle`), LOUD lights orange at 65%+ volume, overdrive at >100%.

**Step 7: Commit**

```bash
git add home/niri/sqlch-popup.py
git commit -m "feat(popup): poll vol/mute/bitrate/bt and drive indicator lights"
```

---

### Task 3: Group label in collapsed bar

**Files:**
- Modify: `home/niri/sqlch-popup.py` (`CollapsedQuickBar` ~line 1714, `_on_group_tab_changed` ~line 2417)

**Step 1: Add group label to `CollapsedQuickBar`**

In `CollapsedQuickBar.__init__`, after `self.append(left_nav)` and before the `for i in range(1, 7)` loop, insert:

```python
self._group_label = Gtk.Label(label="ALL")
self._group_label.add_css_class("collapsed-group-label")
self._group_label.set_halign(Gtk.Align.CENTER)
self._group_label.set_hexpand(False)
self.append(self._group_label)
```

Add `set_group` method to `CollapsedQuickBar`:

```python
def set_group(self, name: str | None):
    self._group_label.set_label(name or "ALL")
```

**Step 2: Call `set_group` when group changes**

Find `_on_group_tab_changed` (~line 2417):
```python
def _on_group_tab_changed(self, group: str | None):
    self._station_list.apply_group(group)
    if self._collapsed:
        self._update_collapsed_bar()
```

Add one line:
```python
def _on_group_tab_changed(self, group: str | None):
    self._station_list.apply_group(group)
    self._collapsed_bar.set_group(group)
    if self._collapsed:
        self._update_collapsed_bar()
```

**Step 3: Add CSS**

Add after the `.quick-num` block (~line 900):

```css
.collapsed-group-label {
  font-family: "JetBrains Mono", monospace;
  font-size: 8px;
  letter-spacing: 0.18em;
  color: #2a6a9a;
  text-shadow: 0 0 5px rgba(42,106,154,0.6);
  min-width: 28px;
  padding: 0 2px;
}
```

**Step 4: Verify visually**

Open popup, collapse station list, cycle groups with ◀/▶. Label should update between `FM1`, `AM1`, `INT1`, `ALL`.

**Step 5: Commit**

```bash
git add home/niri/sqlch-popup.py
git commit -m "feat(popup): show active group name in collapsed bar"
```

---

### Task 4: Physical chassis detail — CSS pass

**Files:**
- Modify: `home/niri/sqlch-popup.py` (CSS section, lines 265–901)

**Step 1: Outer chassis — double bevel**

Find `.popup { ... }` (~line 271). Replace `border` and `box-shadow` with:

```css
.popup {
  background:
    radial-gradient(ellipse 80% 25% at 50% 0%, rgba(30,60,110,0.22) 0%, transparent 100%),
    #0d0d0d;
  border: 1px solid #222;
  border-top: 1px solid #444;
  border-left: 1px solid #444;
  border-radius: 6px;
  outline: 1px solid #111;
  outline-offset: -3px;
  margin: 4px;
  box-shadow:
    0 0 0 1px rgba(0,0,0,0.9),
    0 0 0 2px #181818,
    0 0 0 3px rgba(80,80,80,0.15),
    0 6px 32px rgba(0,0,0,0.95),
    0 0 80px rgba(0,15,50,0.35);
}
```

**Step 2: Screen surround — recess the LCD**

Find `.now-playing { ... }` (~line 287). Extend its `box-shadow` to add a recessed look:

Add to the existing `box-shadow` (or create one if absent):
```css
  box-shadow:
    inset 0 2px 8px rgba(0,0,0,0.85),
    inset 0 -1px 3px rgba(0,0,0,0.5),
    inset 1px 0 4px rgba(0,0,0,0.4),
    inset -1px 0 4px rgba(0,0,0,0.4);
  border-top: 1px solid rgba(255,255,255,0.07);
  border-left: 1px solid rgba(255,255,255,0.04);
```

**Step 3: Screen scuffs — overlay on LCD**

In `.now-playing`, extend `background-image` to stack scuff overlays on top of the existing scanline gradient:

```css
  background-image:
    repeating-linear-gradient(
      0deg,
      transparent,
      transparent 3px,
      rgba(0,0,0,0.10) 3px,
      rgba(0,0,0,0.10) 4px
    ),
    linear-gradient(127deg, transparent 38%, rgba(255,255,255,0.022) 39%, transparent 40%),
    linear-gradient(53deg,  transparent 58%, rgba(255,255,255,0.014) 59%, transparent 60%),
    linear-gradient(161deg, transparent 72%, rgba(255,255,255,0.018) 73%, transparent 74%);
```

**Step 4: Signal zone dot-matrix texture**

Find where `.sig-bar` is defined (sig_area is a `.indicator-panel`). Add to `.indicator-panel`:

```css
.indicator-panel {
  background-image: repeating-linear-gradient(
    0deg,
    transparent,
    transparent 3px,
    rgba(0,30,60,0.25) 3px,
    rgba(0,30,60,0.25) 4px
  );
  border-radius: 2px;
}
```

**Step 5: Seam line CSS**

Add a new class (we'll add the widget in Task 5):

```css
.seam {
  min-height: 1px;
  background: linear-gradient(
    to right,
    transparent 0%,
    #2a2a2a 15%,
    #444 40%,
    #555 50%,
    #444 60%,
    #2a2a2a 85%,
    transparent 100%
  );
  margin: 0;
}
.seam-shadow {
  min-height: 1px;
  background: linear-gradient(
    to right,
    transparent 0%,
    #0a0a0a 15%,
    #111 50%,
    #0a0a0a 85%,
    transparent 100%
  );
  margin: 0;
}
```

**Step 6: Manufacturer badge CSS**

```css
.mfr-badge {
  font-family: "JetBrains Mono", monospace;
  font-size: 7px;
  letter-spacing: 0.20em;
  color: #2a2a2a;
  text-shadow: 0 1px 0 rgba(80,80,80,0.3);
  padding: 2px 8px 1px 0;
}
```

**Step 7: Verify**

Run popup and inspect visually — chassis should look more extruded, LCD should look recessed, faint diagonal scuffs visible on the screen area.

**Step 8: Commit**

```bash
git add home/niri/sqlch-popup.py
git commit -m "feat(popup): physical chassis CSS — bevel, screen recess, scuffs, textures"
```

---

### Task 5: Physical chassis detail — widget pass

**Files:**
- Modify: `home/niri/sqlch-popup.py` (`SqlchPopupWindow.__init__` ~line 2230)

**Step 1: Add manufacturer badge widget**

In `SqlchPopupWindow.__init__`, after `outer = Gtk.Box(...)` and `outer.add_css_class("popup")` but **before** `self.set_child(outer)` (~line 2234):

```python
badge = Gtk.Label(label="SQLCH  ◈  DEH-S")
badge.add_css_class("mfr-badge")
badge.set_halign(Gtk.Align.END)
outer.append(badge)
```

**Step 2: Add seam separators**

Find where `self._div` is appended (the existing divider, ~line 2241):
```python
self._div = Gtk.Separator()
self._div.add_css_class("divider")
outer.append(self._div)
```

Replace with a two-line seam (highlight + shadow):
```python
self._div = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
seam_hi = Gtk.Separator()
seam_hi.add_css_class("seam")
seam_sh = Gtk.Separator()
seam_sh.add_css_class("seam-shadow")
self._div.append(seam_hi)
self._div.append(seam_sh)
outer.append(self._div)
```

Add a second seam between the toolbar and station list. Find where `outer.append(toolbar)` is (~line 2293), then after it:

```python
seam2_hi = Gtk.Separator()
seam2_hi.add_css_class("seam")
seam2_sh = Gtk.Separator()
seam2_sh.add_css_class("seam-shadow")
outer.append(seam2_hi)
outer.append(seam2_sh)
```

**Step 3: Verify visually**

Run popup. Check:
- `SQLCH  ◈  DEH-S` stamp appears top-right, barely visible in dark gray
- Two seam lines visible between LCD zone and toolbar, and between toolbar and station list
- Both seams have a light line above a dark line (highlight/shadow bevel gap illusion)

**Step 4: Commit**

```bash
git add home/niri/sqlch-popup.py
git commit -m "feat(popup): manufacturer badge and seam line widgets"
```

---

### Final: rebuild and smoke test

```bash
nrs
```

Open popup, verify:
- MUTE lights red when `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle`
- ST lights green when stream is playing at ≥128kbps
- MONO lights when stream <128kbps
- LOUD lights orange at 65%+, overdrive bright at >100% or BT connected
- Collapsed bar shows group name (FM1 / AM1 / INT1 / ALL)
- Seams, badge, scuffs, bevel all render correctly
