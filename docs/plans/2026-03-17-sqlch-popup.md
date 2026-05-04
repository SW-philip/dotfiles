# sqlch-popup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a GTK4 layer-shell radio player popup that toggles open/closed when you click a new sqlch widget in ironbar.

**Architecture:** Standalone Python script (`home/niri/sqlch-popup.py`) using GTK4 + gtk4-layer-shell GI bindings, talking directly to sqlch's Unix domain socket. A shell wrapper handles the toggle (kill existing process or start fresh). Packaged via `pkgs.writeShellScriptBin` in `home/niri/default.nix`, same pattern as `toggle-theme`.

**Tech Stack:** Python 3, GTK4 (pygobject3), gtk4-layer-shell (GI typelib via `pkgs.gtk4-layer-shell`), sqlch daemon socket protocol (Unix socket, JSON lines), GdkPixbuf for album art.

---

### Task 1: Write the daemon comms module and test it

The popup talks to sqlch's Unix socket directly — same protocol as `waybar-sqlch`. Before building any UI, verify the comms work.

**Files:**
- Create: `home/niri/sqlch-popup.py` (scaffold only — comms + helpers)

**Step 1: Create the scaffold with only the comms and helper functions**

```python
#!/usr/bin/env python3
"""sqlch-popup — GTK4 layer-shell radio player popup."""

import json
import os
import socket
import subprocess
import hashlib
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
XDG_RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
XDG_CACHE   = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
CONTROL_SOCK = XDG_RUNTIME / "sqlch" / "control.sock"
MPV_SOCK     = XDG_RUNTIME / "sqlch" / "mpv.sock"
CACHE_DIR    = XDG_CACHE / "sqlch"
COVERS_DIR   = CACHE_DIR / "covers"
ENRICHED_JSON = CACHE_DIR / "enriched.json"

POPUP_WIDTH = 320
ART_SIZE    = 64
POLL_MS     = 1500


# ── Daemon comms ───────────────────────────────────────────────────────────────
def daemon_send(msg: dict) -> dict | None:
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(1.5)
        s.connect(str(CONTROL_SOCK))
        s.sendall((json.dumps(msg) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        s.close()
        return json.loads(data.decode("utf-8", errors="replace"))
    except Exception:
        return None


def get_icy_track() -> tuple[str | None, str | None]:
    """Read current ICY metadata from MPV socket. Returns (artist, track)."""
    try:
        cmd = json.dumps({"command": ["get_property", "metadata"]}) + "\n"
        result = subprocess.run(
            ["socat", "-", str(MPV_SOCK)],
            input=cmd.encode(),
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            timeout=1.0,
        )
        resp = json.loads(result.stdout)
        if resp.get("error") == "success":
            meta = resp.get("data") or {}
            icy = meta.get("icy-title") or meta.get("title", "")
            if icy and "-" in icy:
                artist, track = icy.split("-", 1)
                return artist.strip() or None, track.strip() or None
    except Exception:
        pass
    return None, None


def get_cover_path(artist: str, track: str) -> Path | None:
    """Look up cached album art for artist/track. Returns path or None."""
    try:
        enriched = json.loads(ENRICHED_JSON.read_text())
        key = " ".join(artist.lower().split()) + "::" + " ".join(track.lower().split())
        entry = enriched.get(key)
        if not entry:
            return None
        cover_url = entry.get("cover")
        if not cover_url:
            return None
        ext = cover_url.rsplit(".", 1)[-1].split("?")[0] or "jpg"
        fname = hashlib.md5(cover_url.encode()).hexdigest() + "." + ext
        p = COVERS_DIR / fname
        return p if p.exists() else None
    except Exception:
        return None


def get_station_list() -> list[dict]:
    """Get stations from `sqlch list`. Returns [{"id": ..., "name": ...}]."""
    try:
        result = subprocess.run(
            ["sqlch", "list"],
            capture_output=True, text=True, timeout=3
        )
        stations = []
        for line in result.stdout.strip().splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split(None, 1)
            sid  = parts[0]
            name = parts[1] if len(parts) > 1 else sid
            stations.append({"id": sid, "name": name})
        return stations
    except Exception:
        return []
```

**Step 2: Smoke test the comms manually**

With sqlch daemon running, run this in a terminal:

```bash
cd /home/prepko/nixos/home/niri
python3 -c "
from sqlch_popup_test import daemon_send, get_icy_track, get_station_list
print('status:', daemon_send({'cmd': 'status'}))
print('icy:', get_icy_track())
print('stations:', get_station_list()[:3])
"
```

Wait — the file is `sqlch-popup.py` with a dash; Python can't import it directly. Test like this instead:

```bash
python3 - << 'EOF'
import sys; sys.path.insert(0, "/home/prepko/nixos/home/niri")
import importlib.util, pathlib
spec = importlib.util.spec_from_file_location("p", "/home/prepko/nixos/home/niri/sqlch-popup.py")
p = importlib.util.load_from_spec(spec); spec.loader.exec_module(p)
print("status:", p.daemon_send({"cmd": "status"}))
print("stations:", p.get_station_list()[:3])
EOF
```

Expected: status dict with `ok: true` and a `current` key. Stations list with at least one entry.

If daemon is not running, `daemon_send` returns `None` — that's correct, the UI handles it.

**Step 3: Commit**

```bash
git add home/niri/sqlch-popup.py
git commit -m "feat: sqlch-popup scaffold with daemon comms"
```

---

### Task 2: CSS and GTK4 layer-shell window shell

Add the GTK4 imports, CSS, and a minimal window that displays as a layer-shell popup — no widgets yet, just a styled empty box.

**Files:**
- Modify: `home/niri/sqlch-popup.py`

**Step 1: Append the CSS constant and the GTK4 imports to the file**

Add this after the helpers (before `if __name__ == "__main__":`):

```python
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Gtk4LayerShell', '1.0')
gi.require_version('GdkPixbuf', '2.0')
from gi.repository import Gtk, GLib, GdkPixbuf, Gtk4LayerShell

# ── CSS ───────────────────────────────────────────────────────────────────────
CSS = b"""
* { -gtk-icon-style: symbolic; }

window { background: transparent; }

.popup {
  background: #1f1d2e;
  border: 1px solid rgba(168, 96, 119, 0.30);
  border-radius: 12px;
  margin: 4px;
}

.now-playing { padding: 12px; }

.station-name {
  font-family: "JetBrains Mono", monospace;
  font-size: 13px;
  font-weight: 600;
  color: #e0def4;
}

.track-info {
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  color: #908caa;
}

.controls { margin-top: 8px; }

.controls button {
  background: #26233a;
  color: #c4a7e7;
  border: 1px solid rgba(168, 96, 119, 0.25);
  border-radius: 6px;
  padding: 5px 10px;
  font-family: "JetBrains Mono", monospace;
  font-size: 12px;
  min-width: 0;
}

.controls button:hover {
  background: #2e2a42;
  border-color: rgba(168, 96, 119, 0.45);
  color: #e0def4;
}

.divider {
  background-color: rgba(168, 96, 119, 0.18);
  margin: 0 12px;
  min-height: 1px;
}

.station-list { padding: 4px 6px 6px; }

.category-header {
  font-family: "JetBrains Mono", monospace;
  font-size: 9px;
  font-weight: 600;
  letter-spacing: 0.12em;
  color: #6e6a86;
  padding: 6px 8px 2px;
}

.station-row {
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  color: #c4c0d8;
  border-radius: 5px;
  border: none;
  background: transparent;
  padding: 3px 8px;
  min-height: 0;
}

.station-row:hover {
  background: rgba(168, 96, 119, 0.12);
  color: #e0def4;
}

.station-row.active {
  background: #26233a;
  color: #c4a7e7;
}
"""


# ── Window ────────────────────────────────────────────────────────────────────
class SqlchPopupWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_default_size(POPUP_WIDTH, -1)

        # Layer shell setup
        Gtk4LayerShell.init_for_window(self)
        Gtk4LayerShell.set_layer(self, Gtk4LayerShell.Layer.TOP)
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.TOP, True)
        Gtk4LayerShell.set_anchor(self, Gtk4LayerShell.Edge.RIGHT, True)
        Gtk4LayerShell.set_margin(self, Gtk4LayerShell.Edge.TOP, 40)
        Gtk4LayerShell.set_margin(self, Gtk4LayerShell.Edge.RIGHT, 6)
        Gtk4LayerShell.set_keyboard_mode(self, Gtk4LayerShell.KeyboardMode.NONE)

        # Apply CSS
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        # Root box — gets .popup styling
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.add_css_class("popup")
        self.set_child(outer)
        self._outer = outer


class SqlchPopupApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="dev.prepko.sqlch-popup")

    def do_activate(self):
        win = SqlchPopupWindow(self)
        win.present()


if __name__ == "__main__":
    SqlchPopupApp().run()
```

Note: the `gi` imports must come before other imports that depend on them. Move the `import gi` block to the top of the file, before the stdlib imports. The order should be:

```python
#!/usr/bin/env python3
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Gtk4LayerShell', '1.0')
gi.require_version('GdkPixbuf', '2.0')
from gi.repository import Gtk, GLib, GdkPixbuf, Gtk4LayerShell

import json
import os
import socket
import subprocess
import hashlib
from pathlib import Path
# ... rest of file
```

**Step 2: Test that the window appears**

This requires the Nix packaging to be set up (Task 4), so skip visual test here. Continue to Task 3.

---

### Task 3: Build the Now Playing widget

**Files:**
- Modify: `home/niri/sqlch-popup.py` — add `NowPlaying` class, wire into window

**Step 1: Add the NowPlaying class before `SqlchPopupWindow`**

```python
class NowPlaying(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.add_css_class("now-playing")

        # Row: art thumbnail + station name/track info
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.append(row)

        self._art = Gtk.Image()
        self._art.set_pixel_size(ART_SIZE)
        self._art.set_visible(False)
        row.append(self._art)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        info.set_hexpand(True)
        info.set_valign(Gtk.Align.CENTER)
        row.append(info)

        self._name_label = Gtk.Label(label="—")
        self._name_label.add_css_class("station-name")
        self._name_label.set_halign(Gtk.Align.START)
        self._name_label.set_ellipsize(3)  # Pango.EllipsizeMode.END = 3
        info.append(self._name_label)

        self._track_label = Gtk.Label(label="")
        self._track_label.add_css_class("track-info")
        self._track_label.set_halign(Gtk.Align.START)
        self._track_label.set_ellipsize(3)
        self._track_label.set_visible(False)
        info.append(self._track_label)

        # Playback controls
        controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        controls.add_css_class("controls")
        self.append(controls)

        self._btn_prev = self._make_btn("⏮", lambda *_: daemon_send({"cmd": "prev"}))
        self._btn_play = self._make_btn("⏸",  self._on_play_pause)
        self._btn_stop = self._make_btn("⏹",  lambda *_: daemon_send({"cmd": "stop"}))
        self._btn_next = self._make_btn("⏭", lambda *_: daemon_send({"cmd": "next"}))
        for b in [self._btn_prev, self._btn_play, self._btn_stop, self._btn_next]:
            b.set_hexpand(True)
            controls.append(b)

        self._current_id: str | None = None

    def _make_btn(self, label: str, handler) -> Gtk.Button:
        b = Gtk.Button(label=label)
        b.connect("clicked", handler)
        return b

    def _on_play_pause(self, *_):
        daemon_send({"cmd": "pause"})

    def get_current_id(self) -> str | None:
        return self._current_id

    def update(self, resp: dict | None):
        if not resp or not resp.get("ok"):
            self._name_label.set_label("daemon offline")
            self._track_label.set_visible(False)
            self._art.set_visible(False)
            self._current_id = None
            return

        current = resp.get("current")
        status  = resp.get("status", "")
        paused  = "paused" in status.lower()
        self._btn_play.set_label("▶" if paused else "⏸")

        if not current or not isinstance(current, dict):
            self._name_label.set_label("idle")
            self._track_label.set_visible(False)
            self._art.set_visible(False)
            self._current_id = None
            return

        item = current.get("item", {})
        name = item.get("name", "Unknown")
        # Use 'id' field if present, else fall back to name for matching station list
        self._current_id = item.get("id") or name

        self._name_label.set_label(name)

        artist, track = get_icy_track()
        if artist and track:
            self._track_label.set_label(f"{artist} — {track}")
            self._track_label.set_visible(True)
            cover = get_cover_path(artist, track)
            if cover:
                try:
                    pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                        str(cover), ART_SIZE, ART_SIZE, True
                    )
                    self._art.set_from_pixbuf(pb)
                    self._art.set_visible(True)
                except Exception:
                    self._art.set_visible(False)
            else:
                self._art.set_visible(False)
        else:
            self._track_label.set_visible(False)
            self._art.set_visible(False)
```

**Step 2: Add NowPlaying to the window**

In `SqlchPopupWindow.__init__`, after `self._outer = outer`, add:

```python
        self._now_playing = NowPlaying()
        self._outer.append(self._now_playing)

        div = Gtk.Separator()
        div.add_css_class("divider")
        self._outer.append(div)

        # Start polling
        self._poll()
        GLib.timeout_add(POLL_MS, self._poll)

    def _poll(self) -> bool:
        resp = daemon_send({"cmd": "status"})
        self._now_playing.update(resp)
        return True  # keep GLib timer alive
```

---

### Task 4: Build the Station List widget

**Files:**
- Modify: `home/niri/sqlch-popup.py` — add `StationList` class, wire into window

**Step 1: Add the StationList class before `SqlchPopupWindow`**

```python
class StationList(Gtk.Box):
    def __init__(self, on_select):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add_css_class("station-list")
        self._on_select = on_select
        self._buttons: dict[str, Gtk.Button] = {}
        self._active_id: str | None = None

    def _clear(self):
        child = self.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self.remove(child)
            child = nxt
        self._buttons.clear()

    def load(self, stations: list[dict]):
        self._clear()
        for s in stations:
            btn = Gtk.Button(label=s["name"])
            btn.add_css_class("station-row")
            btn.connect("clicked", lambda _, sid=s["id"]: self._on_select(sid))
            self.append(btn)
            self._buttons[s["id"]] = btn
        self.set_active(self._active_id)

    def set_active(self, sid: str | None):
        self._active_id = sid
        for s_id, btn in self._buttons.items():
            if s_id == sid:
                btn.add_css_class("active")
            else:
                btn.remove_css_class("active")
```

**Step 2: Wire StationList into the window**

After the divider in `SqlchPopupWindow.__init__`, add:

```python
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_max_content_height(280)
        scroll.set_propagate_natural_height(True)
        self._outer.append(scroll)

        self._station_list = StationList(self._on_station_select)
        scroll.set_child(self._station_list)
        self._station_list.load(get_station_list())
```

**Step 3: Add `_on_station_select` and update `_poll` to sync active station**

```python
    def _on_station_select(self, station_id: str):
        daemon_send({"cmd": "play", "query": station_id})

    def _poll(self) -> bool:
        resp = daemon_send({"cmd": "status"})
        self._now_playing.update(resp)
        self._station_list.set_active(self._now_playing.get_current_id())
        return True
```

---

### Task 5: Nix packaging

Wire the script into home-manager so `sqlch-popup` is on PATH with the right GI typelib paths.

**Files:**
- Modify: `home/niri/default.nix`

**Step 1: Add the sqlchPopup derivation to the `let` block**

Find the `let` block in `home/niri/default.nix` (it already has `toggleTheme`, `toggleDisplayMode`, etc.). Add after the existing let-bindings and before `in`:

```nix
  sqlchPopupPython = pkgs.python3.withPackages (ps: with ps; [
    pygobject3
  ]);

  sqlchPopup = pkgs.writeShellScriptBin "sqlch-popup" ''
    # Toggle: kill running instance if present, else launch
    if pgrep -f "sqlch-popup.py" > /dev/null 2>&1; then
      pkill -f "sqlch-popup.py"
      exit 0
    fi

    export GI_TYPELIB_PATH="${pkgs.gtk4-layer-shell}/lib/girepository-1.0:${pkgs.gtk4}/lib/girepository-1.0:${pkgs.gdk-pixbuf}/lib/girepository-1.0:$GI_TYPELIB_PATH"
    export LD_LIBRARY_PATH="${pkgs.gtk4-layer-shell}/lib:$LD_LIBRARY_PATH"
    exec ${sqlchPopupPython}/bin/python3 ${./sqlch-popup.py}
  '';
```

**Step 2: Add `sqlchPopup` to `home.packages`**

Find the line:
```nix
  home.packages = [ pkgs.ironbar toggleDisplayMode toggleTheme ];
```

Change it to:
```nix
  home.packages = [ pkgs.ironbar toggleDisplayMode toggleTheme sqlchPopup ];
```

**Step 3: Rebuild and verify the binary is on PATH**

```bash
cd /home/prepko/nixos
sudo nixos-rebuild switch --flake .#$(hostname)
which sqlch-popup
```

Expected: a path like `/home/prepko/.nix-profile/bin/sqlch-popup` or similar.

**Step 4: Run it once to check for import errors**

```bash
sqlch-popup 2>&1
```

Expected: the popup window appears anchored top-right. If you see `gi.repository.Gtk4LayerShell` import errors, double-check `GI_TYPELIB_PATH` — add a debug print in the shell script to verify the path is being set.

If you see a `Namespace Gtk4LayerShell not available` error, the typelib path is wrong. Run:

```bash
find $(nix eval --raw 'nixpkgs#gtk4-layer-shell') -name "*.typelib" 2>/dev/null
```

and use the directory containing `Gtk4LayerShell-1.0.typelib` in `GI_TYPELIB_PATH`.

**Step 5: Commit**

```bash
git add home/niri/sqlch-popup.py home/niri/default.nix
git commit -m "feat: sqlch-popup GTK4 layer-shell radio panel"
```

---

### Task 6: Wire ironbar click trigger

Add a `sqlch` script widget to all three ironbar configs that shows the playing icon and opens the popup on left-click.

**Files:**
- Modify: `home/niri/ironbar-dual.toml`
- Modify: `home/niri/ironbar-single.toml`
- Modify: `home/niri/ironbar.toml`

**Step 1: Add the sqlch widget to `ironbar-dual.toml`**

In the `eDP-1` end section, add before the `wleave` widget:

```toml
[[monitors."eDP-1".end]]
type = "script"
name = "sqlch"
cmd = "waybar-sqlch --status | jq -r '.text'"
mode = "poll"
interval = 2
on_click_left = "sqlch-popup"
on_click_right = "~/.config/waybar/scripts/waybar-sqlch --stop"
on_scroll_up = "~/.config/waybar/scripts/waybar-sqlch --next"
on_scroll_down = "~/.config/waybar/scripts/waybar-sqlch --prev"
```

In the `DP-2` end section, add the same widget before `wleave`.

The DP-3 bottom bar already has a sqlch widget; replace its `on_click_left`:

```toml
# Change this:
on_click_left = "~/.config/waybar/scripts/waybar-sqlch --pause"
# To:
on_click_left = "sqlch-popup"
```

**Step 2: Same changes in `ironbar-single.toml`**

Add the sqlch widget to the `eDP-1` and `DP-2` end sections (before `wleave`), same definition as above.

**Step 3: In `ironbar.toml`, update the existing sqlch widget**

The `sqlch` widget already exists in `ironbar.toml`. Change its `on_click_left`:

```toml
# Find:
on_click_left = "~/.config/waybar/scripts/waybar-sqlch --pause"
# Change to:
on_click_left = "sqlch-popup"
```

**Step 4: Rebuild and restart ironbar**

```bash
sudo nixos-rebuild switch --flake .#$(hostname)
systemctl --user restart ironbar
```

**Step 5: Click the sqlch widget and verify the popup opens**

Expected: clicking the sqlch icon in the bar opens a ~320px panel anchored top-right with now-playing info and station list. Clicking again closes it.

**Step 6: Commit**

```bash
git add home/niri/ironbar-dual.toml home/niri/ironbar-single.toml home/niri/ironbar.toml
git commit -m "feat: wire sqlch-popup to ironbar click"
```

---

### Task 7: Smoke test checklist

Run through this manually after the rebuild:

- [ ] sqlch playing → popup shows station name
- [ ] ICY metadata present → artist/track shows under station name
- [ ] Album art cached → thumbnail appears
- [ ] ⏸ button → pauses; icon changes to ▶
- [ ] ▶ button → resumes
- [ ] ⏹ button → stops; popup shows "idle"
- [ ] ⏮/⏭ → switches station; name updates within 1.5s
- [ ] Click station row → switches to that station; row highlights
- [ ] Daemon offline → popup shows "daemon offline" without crashing
- [ ] Click ironbar widget twice → popup opens then closes

If any check fails, the most common issues:
- **Popup not appearing**: check `journalctl --user -u ironbar` for errors in the click handler
- **Layer shell error**: verify `GI_TYPELIB_PATH` contains the `Gtk4LayerShell-1.0.typelib` directory
- **Art not loading**: verify `~/.cache/sqlch/enriched.json` has entries and covers dir has `.jpg` files
- **Station list empty**: run `sqlch list` in a terminal; if it fails, sqlch daemon may not be in PATH when ironbar launches it — check the shell wrapper's PATH

---

### Notes on the complete `sqlch-popup.py`

The final file assembles all four tasks in order:

1. `import gi` + version requires + `from gi.repository` imports (top)
2. stdlib imports
3. Path constants
4. `daemon_send`, `get_icy_track`, `get_cover_path`, `get_station_list` functions
5. `CSS` bytes constant
6. `NowPlaying(Gtk.Box)` class
7. `StationList(Gtk.Box)` class
8. `SqlchPopupWindow(Gtk.ApplicationWindow)` class
9. `SqlchPopupApp(Gtk.Application)` class
10. `if __name__ == "__main__": SqlchPopupApp().run()`
