# sqlch-popup Pioneer Toggle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire ironbar's sqlch widget to toggle `sqlch-popup` open/close on left-click, and restyle the popup to look like a 2000s Pioneer DEH head unit with blue backlight LCD aesthetic.

**Architecture:** A small toggle shell script handles the open/kill logic via PID file. Ironbar config `on_click_left` is updated to call it. The popup's embedded CSS is replaced wholesale with a Pioneer-inspired dark chassis + blue LCD theme.

**Tech Stack:** Bash (toggle script), TOML (ironbar config), Python/GTK4 CSS (popup styling)

---

### Task 1: Write the toggle script

**Files:**
- Create: `home/niri/sqlch-popup-toggle` (will be deployed to `~/.config/waybar/scripts/sqlch-popup-toggle`)

**Step 1: Create the script**

```bash
#!/usr/bin/env bash
# Toggle sqlch-popup: kill if running, launch if not.
PIDFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sqlch/popup.pid"

if [ -f "$PIDFILE" ]; then
    pid=$(cat "$PIDFILE")
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        rm -f "$PIDFILE"
        exit 0
    fi
    rm -f "$PIDFILE"
fi

sqlch-popup &
echo $! > "$PIDFILE"
```

**Step 2: Make it executable**

```bash
chmod +x home/niri/sqlch-popup-toggle
```

**Step 3: Verify it runs without error (daemon must be running for full test)**

```bash
bash -n home/niri/sqlch-popup-toggle && echo "syntax ok"
```

Expected: `syntax ok`

**Step 4: Commit**

```bash
git add home/niri/sqlch-popup-toggle
git commit -m "feat: add sqlch-popup-toggle script"
```

---

### Task 2: Wire the toggle into ironbar config

**Files:**
- Modify: `home/niri/ironbar.toml` — two sqlch widgets (eDP-1 and DP-3)

**Step 1: Update eDP-1 sqlch widget**

In `home/niri/ironbar.toml`, find the `eDP-1` sqlch widget (around line 65–75) and change:
```toml
on_click_left = "~/.config/waybar/scripts/waybar-sqlch --pause"
```
to:
```toml
on_click_left = "sqlch-popup-toggle"
```

**Step 2: Update DP-3 sqlch widget**

Find the `DP-3` sqlch widget (around line 180–188) and make the same change:
```toml
on_click_left = "sqlch-popup-toggle"
```

**Step 3: Verify TOML is valid**

```bash
python3 -c "import tomllib; tomllib.loads(open('home/niri/ironbar.toml').read()); print('valid')"
```

Expected: `valid`

**Step 4: Commit**

```bash
git add home/niri/ironbar.toml
git commit -m "feat: wire ironbar sqlch click to sqlch-popup-toggle"
```

---

### Task 3: Wire the toggle into NixOS (deploy script + PATH)

**Files:**
- Locate: how existing waybar scripts are deployed (check `home/niri/` nix files, `home.nix` or similar)

**Step 1: Find how other scripts are deployed**

```bash
grep -r "sqlch-popup\|waybar-sqlch\|sqlch-popup-toggle" /home/prepko/nixos --include="*.nix" -l
```

**Step 2: Add `sqlch-popup-toggle` alongside `sqlch-popup` in the nix config**

Find the existing `sqlch-popup` entry and add the toggle script in the same pattern. For example if it's in `home/niri/default.nix` as a `home.file` entry:

```nix
home.file.".config/waybar/scripts/sqlch-popup-toggle" = {
  source = ./sqlch-popup-toggle;
  executable = true;
};
```

**Step 3: Commit**

```bash
git add home/niri/default.nix   # or whichever nix file was modified
git commit -m "feat: deploy sqlch-popup-toggle via nix home-manager"
```

---

### Task 4: Restyle sqlch-popup with Pioneer DEH blue LCD theme

**Files:**
- Modify: `home/niri/sqlch-popup.py` — replace the `CSS` constant

**Step 1: Replace the CSS constant (lines 33–116)**

Replace the entire `CSS = b"""..."""` block with:

```python
CSS = b"""
* { -gtk-icon-style: symbolic; }

window { background: transparent; }

/* ── Outer chassis ── */
.popup {
  background: #0d0d0d;
  border: 1px solid #3a3a3a;
  border-top: 1px solid #555;
  border-left: 1px solid #555;
  border-radius: 6px;
  margin: 4px;
  box-shadow: 0 4px 24px rgba(0,0,0,0.85), inset 0 1px 0 rgba(255,255,255,0.06);
}

/* ── LCD display panel (now-playing area) ── */
.now-playing {
  background: #050810;
  border-radius: 4px 4px 0 0;
  padding: 10px 12px;
  border-bottom: 1px solid #0a1628;
  box-shadow: inset 0 0 12px rgba(0, 80, 180, 0.15);
}

/* Station name — bright blue LCD */
.station-name {
  font-family: "JetBrains Mono", "Courier New", monospace;
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.08em;
  color: #5bc8ff;
  text-shadow: 0 0 8px rgba(91, 200, 255, 0.85), 0 0 20px rgba(60, 150, 255, 0.4);
}

/* Track info — dimmer blue-gray */
.track-info {
  font-family: "JetBrains Mono", "Courier New", monospace;
  font-size: 10px;
  letter-spacing: 0.05em;
  color: #2a7ab5;
  text-shadow: 0 0 6px rgba(42, 122, 181, 0.6);
}

/* ── Transport controls ── */
.controls { margin-top: 8px; }

.controls button {
  background: linear-gradient(180deg, #222 0%, #141414 60%, #1a1a1a 100%);
  color: #8ad4f5;
  border: 1px solid #2a2a2a;
  border-top: 1px solid #3a3a3a;
  border-radius: 4px;
  padding: 5px 10px;
  font-family: "JetBrains Mono", monospace;
  font-size: 13px;
  min-width: 0;
  box-shadow: 0 2px 4px rgba(0,0,0,0.7), inset 0 1px 0 rgba(255,255,255,0.05);
  text-shadow: 0 0 6px rgba(91, 200, 255, 0.5);
}

.controls button:hover {
  background: linear-gradient(180deg, #1a2a3a 0%, #0f1e2e 100%);
  border-color: #1e5a8a;
  color: #5bc8ff;
  box-shadow: 0 0 8px rgba(30, 90, 180, 0.4), inset 0 1px 0 rgba(91,200,255,0.1);
  text-shadow: 0 0 10px rgba(91, 200, 255, 0.9);
}

.controls button:active {
  background: #070f1a;
  box-shadow: inset 0 2px 4px rgba(0,0,0,0.8);
}

/* ── Divider ── */
.divider {
  background-color: #0e2540;
  margin: 0;
  min-height: 1px;
  box-shadow: 0 1px 0 rgba(91,200,255,0.08);
}

/* ── Station list ── */
.station-list {
  padding: 2px 4px 4px;
  background: #0a0a0a;
  border-radius: 0 0 5px 5px;
}

.station-row {
  font-family: "JetBrains Mono", "Courier New", monospace;
  font-size: 11px;
  letter-spacing: 0.04em;
  color: #2a6a9a;
  border-radius: 3px;
  border: none;
  background: transparent;
  padding: 3px 8px;
  min-height: 0;
  text-shadow: 0 0 4px rgba(42, 106, 154, 0.4);
}

.station-row:hover {
  background: rgba(30, 90, 160, 0.15);
  color: #4ab4e8;
  text-shadow: 0 0 8px rgba(74, 180, 232, 0.6);
}

.station-row.active {
  background: rgba(30, 90, 160, 0.25);
  color: #5bc8ff;
  text-shadow: 0 0 10px rgba(91, 200, 255, 0.8);
}
"""
```

**Step 2: Also bump POPUP_WIDTH to 340 (line 29)**

Change:
```python
POPUP_WIDTH = 320
```
to:
```python
POPUP_WIDTH = 340
```

**Step 3: Visual smoke-test**

```bash
python3 home/niri/sqlch-popup.py &
sleep 2
kill %1
```

Expected: popup appears with dark chassis + blue glow, no Python errors on stdout.

**Step 4: Commit**

```bash
git add home/niri/sqlch-popup.py
git commit -m "feat: restyle sqlch-popup with Pioneer DEH blue LCD theme"
```

---

### Task 5: Rebuild and test live

**Step 1: Apply NixOS config**

```bash
sudo nixos-rebuild switch --flake .#
```

**Step 2: Restart ironbar**

```bash
pkill ironbar; ironbar &
```

**Step 3: Click the sqlch widget — popup should open**

**Step 4: Click again — popup should close**

**Step 5: Verify scroll-up/down and right-click still control sqlch (next/prev/stop)**
