# Uniremote Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a GTK4 Python universal remote app for Samsung TV (SmartThings API) and Roku (ECP), packaged as a Nix derivation in `pkgs/uniremote/`.

**Architecture:** Two Python files — `uniremote_api.py` holds pure testable logic (Config, SmartThingsAPI, RokuAPI, SSDP discovery); `uniremote_gtk.py` holds the GTK4 UI and imports from it. Single `Gtk.ApplicationWindow` with a `Gtk.Notebook` (Samsung tab, Roku tab, Settings tab). HTTP calls run in background threads with `GLib.idle_add` for UI callbacks.

**Tech Stack:** Python 3, GTK4/PyGObject, `requests`, stdlib `socket`/`xml.etree`/`tomllib`/`threading`, NixOS (package in `pkgs/uniremote/`)

---

## Task 1: Scaffold files and Config class

**Files:**
- Create: `pkgs/uniremote/uniremote_api.py`
- Create: `pkgs/uniremote/tests/__init__.py`
- Create: `pkgs/uniremote/tests/test_config.py`

**Step 1: Create the test file**

```python
# pkgs/uniremote/tests/test_config.py
import os, sys, tempfile, pytest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from uniremote_api import Config

def test_default_config_created(tmp_path):
    cfg = Config(path=tmp_path / "config.toml")
    assert cfg.samsung_token == ""
    assert cfg.samsung_device_id == ""
    assert cfg.roku_ip == ""

def test_save_and_reload(tmp_path):
    path = tmp_path / "config.toml"
    cfg = Config(path=path)
    cfg.samsung_token = "tok123"
    cfg.samsung_device_id = "dev456"
    cfg.roku_ip = "192.168.1.50"
    cfg.save()

    cfg2 = Config(path=path)
    assert cfg2.samsung_token == "tok123"
    assert cfg2.samsung_device_id == "dev456"
    assert cfg2.roku_ip == "192.168.1.50"

def test_config_file_written(tmp_path):
    path = tmp_path / "config.toml"
    cfg = Config(path=path)
    cfg.samsung_token = "t"
    cfg.save()
    content = path.read_text()
    assert "[samsung]" in content
    assert "[roku]" in content
```

**Step 2: Run tests — expect failure**

```bash
cd ~/nixos
python3 -m pytest pkgs/uniremote/tests/test_config.py -v
```
Expected: `ModuleNotFoundError: No module named 'uniremote_api'`

**Step 3: Implement Config in uniremote_api.py**

```python
# pkgs/uniremote/uniremote_api.py
from __future__ import annotations
import os, sys, tomllib
from pathlib import Path

DEFAULT_CONFIG_PATH = Path.home() / ".config" / "uniremote" / "config.toml"

def _write_toml(data: dict) -> str:
    lines = []
    for section, values in data.items():
        lines.append(f"[{section}]")
        for key, val in values.items():
            lines.append(f'{key} = "{val}"')
        lines.append("")
    return "\n".join(lines)

class Config:
    def __init__(self, path: Path = DEFAULT_CONFIG_PATH):
        self.path = Path(path)
        self.samsung_token = ""
        self.samsung_device_id = ""
        self.roku_ip = ""
        self._load()

    def _load(self):
        if not self.path.exists():
            return
        with open(self.path, "rb") as f:
            data = tomllib.load(f)
        samsung = data.get("samsung", {})
        roku = data.get("roku", {})
        self.samsung_token = samsung.get("token", "")
        self.samsung_device_id = samsung.get("device_id", "")
        self.roku_ip = roku.get("ip", "")

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        data = {
            "samsung": {"token": self.samsung_token, "device_id": self.samsung_device_id},
            "roku": {"ip": self.roku_ip},
        }
        self.path.write_text(_write_toml(data))
```

**Step 4: Run tests — expect pass**

```bash
python3 -m pytest pkgs/uniremote/tests/test_config.py -v
```
Expected: 3 PASSED

**Step 5: Commit**

```bash
git add pkgs/uniremote/uniremote_api.py pkgs/uniremote/tests/
git commit -m "feat(uniremote): add Config class with toml read/write"
```

---

## Task 2: SmartThings API class

**Files:**
- Modify: `pkgs/uniremote/uniremote_api.py`
- Create: `pkgs/uniremote/tests/test_smartthings.py`

**Step 1: Write tests**

```python
# pkgs/uniremote/tests/test_smartthings.py
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from unittest.mock import patch, MagicMock
from uniremote_api import SmartThingsAPI

TOKEN = "mytoken"
DEVICE_ID = "device-abc"

def _api():
    return SmartThingsAPI(TOKEN, DEVICE_ID)

def test_send_key(requests_mock):
    url = f"https://api.smartthings.com/v1/devices/{DEVICE_ID}/commands"
    requests_mock.post(url, json={"results": [{"status": "ACCEPTED"}]})
    api = _api()
    api.send_key("KEY_UP")
    assert requests_mock.last_request.json() == {
        "commands": [{
            "component": "main",
            "capability": "samsungvd.remoteControl",
            "command": "sendKey",
            "arguments": ["KEY_UP"],
        }]
    }

def test_power_on(requests_mock):
    url = f"https://api.smartthings.com/v1/devices/{DEVICE_ID}/commands"
    requests_mock.post(url, json={})
    _api().power("on")
    body = requests_mock.last_request.json()
    assert body["commands"][0]["capability"] == "switch"
    assert body["commands"][0]["command"] == "on"

def test_volume_up(requests_mock):
    url = f"https://api.smartthings.com/v1/devices/{DEVICE_ID}/commands"
    requests_mock.post(url, json={})
    _api().volume_up()
    body = requests_mock.last_request.json()
    assert body["commands"][0]["capability"] == "audioVolume"
    assert body["commands"][0]["command"] == "volumeUp"

def test_channel_up(requests_mock):
    url = f"https://api.smartthings.com/v1/devices/{DEVICE_ID}/commands"
    requests_mock.post(url, json={})
    _api().channel_up()
    body = requests_mock.last_request.json()
    assert body["commands"][0]["capability"] == "tvChannel"
    assert body["commands"][0]["command"] == "channelUp"

def test_fetch_devices(requests_mock):
    requests_mock.get(
        "https://api.smartthings.com/v1/devices",
        json={"items": [
            {"deviceId": "d1", "label": "Living Room TV", "deviceTypeName": "Samsung TV"},
            {"deviceId": "d2", "label": "Phone", "deviceTypeName": "Mobile"},
        ]}
    )
    devs = SmartThingsAPI.fetch_devices(TOKEN)
    assert len(devs) == 2
    assert devs[0] == ("d1", "Living Room TV")
```

**Step 2: Run tests — expect failure**

```bash
python3 -m pytest pkgs/uniremote/tests/test_smartthings.py -v
```
Expected: FAILED — `ImportError: cannot import name 'SmartThingsAPI'`

Note: Install `pytest-requests-mock` if needed: `pip install requests-mock pytest`

**Step 3: Implement SmartThingsAPI**

Append to `uniremote_api.py`:

```python
import requests

ST_BASE = "https://api.smartthings.com/v1"

class SmartThingsAPI:
    def __init__(self, token: str, device_id: str):
        self.token = token
        self.device_id = device_id
        self._headers = {"Authorization": f"Bearer {token}"}

    def _command(self, capability: str, command: str, arguments: list = None):
        cmd = {"component": "main", "capability": capability, "command": command}
        if arguments:
            cmd["arguments"] = arguments
        requests.post(
            f"{ST_BASE}/devices/{self.device_id}/commands",
            headers=self._headers,
            json={"commands": [cmd]},
            timeout=5,
        )

    def send_key(self, key: str):
        self._command("samsungvd.remoteControl", "sendKey", [key])

    def power(self, state: str):  # state: "on" or "off"
        self._command("switch", state)

    def volume_up(self):
        self._command("audioVolume", "volumeUp")

    def volume_down(self):
        self._command("audioVolume", "volumeDown")

    def channel_up(self):
        self._command("tvChannel", "channelUp")

    def channel_down(self):
        self._command("tvChannel", "channelDown")

    @staticmethod
    def fetch_devices(token: str) -> list[tuple[str, str]]:
        resp = requests.get(
            f"{ST_BASE}/devices",
            headers={"Authorization": f"Bearer {token}"},
            timeout=5,
        )
        resp.raise_for_status()
        items = resp.json().get("items", [])
        return [(d["deviceId"], d.get("label", d["deviceId"])) for d in items]
```

**Step 4: Run tests — expect pass**

```bash
python3 -m pytest pkgs/uniremote/tests/test_smartthings.py -v
```
Expected: 5 PASSED

**Step 5: Commit**

```bash
git add pkgs/uniremote/uniremote_api.py pkgs/uniremote/tests/test_smartthings.py
git commit -m "feat(uniremote): add SmartThingsAPI class"
```

---

## Task 3: Roku ECP API class

**Files:**
- Modify: `pkgs/uniremote/uniremote_api.py`
- Create: `pkgs/uniremote/tests/test_roku.py`

**Step 1: Write tests**

```python
# pkgs/uniremote/tests/test_roku.py
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from uniremote_api import RokuAPI

IP = "192.168.1.100"

def _api():
    return RokuAPI(IP)

def test_keypress(requests_mock):
    requests_mock.post(f"http://{IP}:8060/keypress/Up", text="")
    _api().keypress("Up")
    assert requests_mock.called

def test_list_apps(requests_mock):
    xml = """<?xml version="1.0" encoding="UTF-8" ?>
    <apps>
      <app id="12" version="4.1">Netflix</app>
      <app id="2285" version="3.0">Hulu</app>
    </apps>"""
    requests_mock.get(f"http://{IP}:8060/query/apps", text=xml)
    apps = _api().list_apps()
    assert apps == [("12", "Netflix"), ("2285", "Hulu")]

def test_launch_app(requests_mock):
    requests_mock.post(f"http://{IP}:8060/launch/12", text="")
    _api().launch_app("12")
    assert requests_mock.called

def test_search(requests_mock):
    requests_mock.post(f"http://{IP}:8060/search/browse", text="")
    _api().search("stranger things")
    assert requests_mock.last_request.qs == {
        "keyword": ["stranger things"], "launch": ["true"]
    }
```

**Step 2: Run tests — expect failure**

```bash
python3 -m pytest pkgs/uniremote/tests/test_roku.py -v
```
Expected: FAILED — `ImportError: cannot import name 'RokuAPI'`

**Step 3: Implement RokuAPI**

Append to `uniremote_api.py`:

```python
import xml.etree.ElementTree as ET

class RokuAPI:
    def __init__(self, ip: str):
        self.base = f"http://{ip}:8060"

    def keypress(self, key: str):
        requests.post(f"{self.base}/keypress/{key}", timeout=3)

    def list_apps(self) -> list[tuple[str, str]]:
        resp = requests.get(f"{self.base}/query/apps", timeout=5)
        resp.raise_for_status()
        root = ET.fromstring(resp.text)
        return [(app.get("id", ""), app.text or "") for app in root.findall("app")]

    def launch_app(self, app_id: str):
        requests.post(f"{self.base}/launch/{app_id}", timeout=3)

    def search(self, query: str):
        requests.post(
            f"{self.base}/search/browse",
            params={"keyword": query, "launch": "true"},
            timeout=3,
        )
```

**Step 4: Run tests — expect pass**

```bash
python3 -m pytest pkgs/uniremote/tests/test_roku.py -v
```
Expected: 4 PASSED

**Step 5: Commit**

```bash
git add pkgs/uniremote/uniremote_api.py pkgs/uniremote/tests/test_roku.py
git commit -m "feat(uniremote): add RokuAPI class"
```

---

## Task 4: SSDP discovery

**Files:**
- Modify: `pkgs/uniremote/uniremote_api.py`
- Create: `pkgs/uniremote/tests/test_ssdp.py`

**Step 1: Write tests**

```python
# pkgs/uniremote/tests/test_ssdp.py
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from unittest.mock import patch, MagicMock
from uniremote_api import discover_roku

SSDP_RESPONSE = (
    b"HTTP/1.1 200 OK\r\n"
    b"ST: roku:ecp\r\n"
    b"Location: http://192.168.1.77:8060/\r\n"
    b"\r\n"
)

def test_discover_finds_roku():
    mock_sock = MagicMock()
    mock_sock.recvfrom.side_effect = [
        (SSDP_RESPONSE, ("192.168.1.77", 1900)),
        TimeoutError(),
    ]
    with patch("socket.socket", return_value=mock_sock):
        result = discover_roku(timeout=1)
    assert result == "192.168.1.77"

def test_discover_returns_none_on_timeout():
    mock_sock = MagicMock()
    mock_sock.recvfrom.side_effect = TimeoutError()
    with patch("socket.socket", return_value=mock_sock):
        result = discover_roku(timeout=1)
    assert result is None
```

**Step 2: Run tests — expect failure**

```bash
python3 -m pytest pkgs/uniremote/tests/test_ssdp.py -v
```
Expected: FAILED — `ImportError: cannot import name 'discover_roku'`

**Step 3: Implement discover_roku**

Append to `uniremote_api.py`:

```python
import socket

SSDP_ADDR = "239.255.255.250"
SSDP_PORT = 1900
SSDP_MX = 2
SSDP_ST = "roku:ecp"
SSDP_MSG = (
    "M-SEARCH * HTTP/1.1\r\n"
    f"HOST: {SSDP_ADDR}:{SSDP_PORT}\r\n"
    "MAN: \"ssdp:discover\"\r\n"
    f"MX: {SSDP_MX}\r\n"
    f"ST: {SSDP_ST}\r\n"
    "\r\n"
).encode()

def discover_roku(timeout: int = 3) -> str | None:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP) as sock:
        sock.settimeout(timeout)
        sock.sendto(SSDP_MSG, (SSDP_ADDR, SSDP_PORT))
        while True:
            try:
                data, _ = sock.recvfrom(1024)
                response = data.decode(errors="ignore")
                if "roku:ecp" in response.lower():
                    for line in response.splitlines():
                        if line.lower().startswith("location:"):
                            url = line.split(":", 1)[1].strip()
                            # url like http://192.168.1.77:8060/
                            ip = url.split("//")[1].split(":")[0]
                            return ip
            except (TimeoutError, OSError):
                return None
```

**Step 4: Run tests — expect pass**

```bash
python3 -m pytest pkgs/uniremote/tests/test_ssdp.py -v
```
Expected: 2 PASSED

**Step 5: Run all tests**

```bash
python3 -m pytest pkgs/uniremote/tests/ -v
```
Expected: All PASSED

**Step 6: Commit**

```bash
git add pkgs/uniremote/uniremote_api.py pkgs/uniremote/tests/test_ssdp.py
git commit -m "feat(uniremote): add SSDP Roku discovery"
```

---

## Task 5: GTK4 app skeleton

**Files:**
- Create: `pkgs/uniremote/uniremote_gtk.py`

**Step 1: Create the GTK4 skeleton**

```python
#!/usr/bin/env python3
# pkgs/uniremote/uniremote_gtk.py
import sys
import threading
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, GLib

try:
    from uniremote_api import Config, SmartThingsAPI, RokuAPI, discover_roku
except ImportError:
    import os
    sys.path.insert(0, os.path.dirname(__file__))
    from uniremote_api import Config, SmartThingsAPI, RokuAPI, discover_roku

config = Config()


def run_async(fn, *args, callback=None):
    """Run fn(*args) in a thread; call callback(result) on main thread."""
    def worker():
        try:
            result = fn(*args)
        except Exception as e:
            result = e
        if callback:
            GLib.idle_add(callback, result)
    threading.Thread(target=worker, daemon=True).start()


class UniremoteApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="com.prepko.uniremote")

    def do_activate(self):
        win = MainWindow(application=self)
        win.present()


class MainWindow(Gtk.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(title="Uniremote", default_width=360, default_height=600, **kwargs)
        notebook = Gtk.Notebook()
        notebook.append_page(SamsungTab(), Gtk.Label(label="Samsung"))
        notebook.append_page(RokuTab(), Gtk.Label(label="Roku"))
        notebook.append_page(SettingsTab(), Gtk.Label(label="Settings"))
        self.set_child(notebook)


class SamsungTab(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin_top=12,
                         margin_bottom=12, margin_start=12, margin_end=12)
        self.add_css_class("samsung-tab")
        lbl = Gtk.Label(label="Samsung TV")
        lbl.add_css_class("title-2")
        self.append(lbl)
        # Placeholder — wired in Task 6
        self.append(Gtk.Label(label="(controls coming in Task 6)"))


class RokuTab(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin_top=12,
                         margin_bottom=12, margin_start=12, margin_end=12)
        lbl = Gtk.Label(label="Roku")
        lbl.add_css_class("title-2")
        self.append(lbl)
        self.append(Gtk.Label(label="(controls coming in Task 7-8)"))


class SettingsTab(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin_top=12,
                         margin_bottom=12, margin_start=12, margin_end=12)
        lbl = Gtk.Label(label="Settings")
        lbl.add_css_class("title-2")
        self.append(lbl)
        self.append(Gtk.Label(label="(settings coming in Task 9)"))


def main():
    app = UniremoteApp()
    sys.exit(app.run(sys.argv))


if __name__ == "__main__":
    main()
```

**Step 2: Smoke test (requires display/Wayland)**

```bash
python3 pkgs/uniremote/uniremote_gtk.py
```
Expected: Window opens with 3 tabs, no errors

**Step 3: Commit**

```bash
git add pkgs/uniremote/uniremote_gtk.py
git commit -m "feat(uniremote): add GTK4 app skeleton with 3-tab notebook"
```

---

## Task 6: Samsung tab controls

**Files:**
- Modify: `pkgs/uniremote/uniremote_gtk.py` — replace `SamsungTab` class

**Step 1: Replace SamsungTab with full controls**

Replace the `SamsungTab` class in `uniremote_gtk.py`:

```python
class SamsungTab(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                         margin_top=12, margin_bottom=12, margin_start=12, margin_end=12)
        lbl = Gtk.Label(label="Samsung TV")
        lbl.add_css_class("title-2")
        self.append(lbl)

        def btn(label, on_click):
            b = Gtk.Button(label=label)
            b.connect("clicked", lambda _: on_click())
            return b

        def st():
            return SmartThingsAPI(config.samsung_token, config.samsung_device_id)

        # Power row
        power_box = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        power_box.append(btn("⏻ On",  lambda: run_async(st().power, "on")))
        power_box.append(btn("⏻ Off", lambda: run_async(st().power, "off")))
        self.append(power_box)

        # D-pad
        dpad = Gtk.Grid(row_spacing=4, column_spacing=4, halign=Gtk.Align.CENTER)
        dpad.attach(btn("▲", lambda: run_async(st().send_key, "KEY_UP")),    1, 0, 1, 1)
        dpad.attach(btn("◀", lambda: run_async(st().send_key, "KEY_LEFT")),  0, 1, 1, 1)
        dpad.attach(btn("OK", lambda: run_async(st().send_key, "KEY_ENTER")), 1, 1, 1, 1)
        dpad.attach(btn("▶", lambda: run_async(st().send_key, "KEY_RIGHT")), 2, 1, 1, 1)
        dpad.attach(btn("▼", lambda: run_async(st().send_key, "KEY_DOWN")),  1, 2, 1, 1)
        self.append(dpad)

        # Back / Home
        nav_box = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        nav_box.append(btn("⬅ Back", lambda: run_async(st().send_key, "KEY_RETURN")))
        nav_box.append(btn("⌂ Home", lambda: run_async(st().send_key, "KEY_HOME")))
        self.append(nav_box)

        # Volume / Channel
        vc_grid = Gtk.Grid(row_spacing=4, column_spacing=8, halign=Gtk.Align.CENTER)
        vc_grid.attach(Gtk.Label(label="Vol"),  0, 0, 1, 1)
        vc_grid.attach(btn("▲", lambda: run_async(st().volume_up)),   0, 1, 1, 1)
        vc_grid.attach(btn("▼", lambda: run_async(st().volume_down)), 0, 2, 1, 1)
        vc_grid.attach(Gtk.Label(label="Ch"),   1, 0, 1, 1)
        vc_grid.attach(btn("▲", lambda: run_async(st().channel_up)),  1, 1, 1, 1)
        vc_grid.attach(btn("▼", lambda: run_async(st().channel_down)),1, 2, 1, 1)
        self.append(vc_grid)
```

**Step 2: Smoke test**

```bash
python3 pkgs/uniremote/uniremote_gtk.py
```
Expected: Samsung tab shows power, d-pad, back/home, vol/ch controls

**Step 3: Commit**

```bash
git add pkgs/uniremote/uniremote_gtk.py
git commit -m "feat(uniremote): wire Samsung tab with all controls"
```

---

## Task 7: Roku remote tab

**Files:**
- Modify: `pkgs/uniremote/uniremote_gtk.py` — replace `RokuTab` class

**Step 1: Replace RokuTab with remote controls**

Replace the `RokuTab` class:

```python
class RokuTab(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                         margin_top=12, margin_bottom=12, margin_start=12, margin_end=12)
        lbl = Gtk.Label(label="Roku")
        lbl.add_css_class("title-2")
        self.append(lbl)

        def btn(label, key):
            b = Gtk.Button(label=label)
            b.connect("clicked", lambda _: run_async(self._roku().keypress, key))
            return b

        # Power
        self.append(btn("⏻ Power", "PowerOff"))

        # D-pad
        dpad = Gtk.Grid(row_spacing=4, column_spacing=4, halign=Gtk.Align.CENTER)
        dpad.attach(btn("▲", "Up"),     1, 0, 1, 1)
        dpad.attach(btn("◀", "Left"),   0, 1, 1, 1)
        dpad.attach(btn("OK", "Select"),1, 1, 1, 1)
        dpad.attach(btn("▶", "Right"),  2, 1, 1, 1)
        dpad.attach(btn("▼", "Down"),   1, 2, 1, 1)
        self.append(dpad)

        # Back / Home
        nav = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        nav.append(btn("⬅ Back", "Back"))
        nav.append(btn("⌂ Home", "Home"))
        self.append(nav)

        # Media transport
        media = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        media.append(btn("⏮", "Rev"))
        media.append(btn("⏯", "Play"))
        media.append(btn("⏭", "Fwd"))
        self.append(media)

        # Volume
        vol = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        vol.append(btn("🔉", "VolumeDown"))
        vol.append(btn("🔇", "VolumeMute"))
        vol.append(btn("🔊", "VolumeUp"))
        self.append(vol)

        # Search
        search_btn = Gtk.Button(label="🔍 Search")
        search_btn.connect("clicked", self._on_search)
        self.append(search_btn)

        # Apps list (populated later)
        self.apps_box = Gtk.FlowBox(max_children_per_line=3, selection_mode=Gtk.SelectionMode.NONE,
                                     row_spacing=4, column_spacing=4)
        scroll = Gtk.ScrolledWindow(vexpand=True)
        scroll.set_child(self.apps_box)
        self.append(scroll)

        # Load apps async
        run_async(self._load_apps_data, callback=self._populate_apps)

    def _roku(self):
        return RokuAPI(config.roku_ip)

    def _load_apps_data(self):
        if not config.roku_ip:
            return []
        return self._roku().list_apps()

    def _populate_apps(self, apps):
        if not apps or isinstance(apps, Exception):
            return
        for child in list(self.apps_box):
            self.apps_box.remove(child)
        for app_id, name in apps:
            b = Gtk.Button(label=name)
            b.connect("clicked", lambda _, aid=app_id: run_async(self._roku().launch_app, aid))
            self.apps_box.append(b)

    def _on_search(self, _):
        dialog = Gtk.Dialog(title="Search Roku", transient_for=self.get_root(), modal=True)
        dialog.set_default_size(300, 100)
        entry = Gtk.Entry(placeholder_text="Search…")
        entry.connect("activate", lambda e: self._do_search(e.get_text(), dialog))
        go = Gtk.Button(label="Search")
        go.connect("clicked", lambda _: self._do_search(entry.get_text(), dialog))
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                      margin_top=12, margin_bottom=12, margin_start=12, margin_end=12)
        box.append(entry)
        box.append(go)
        dialog.set_child(box)
        dialog.present()

    def _do_search(self, query: str, dialog):
        if query.strip():
            run_async(self._roku().search, query.strip())
        dialog.close()
```

**Step 2: Smoke test**

```bash
python3 pkgs/uniremote/uniremote_gtk.py
```
Expected: Roku tab shows full remote, search button, scrollable apps area (empty if no IP set)

**Step 3: Commit**

```bash
git add pkgs/uniremote/uniremote_gtk.py
git commit -m "feat(uniremote): wire Roku tab with remote, search, app list"
```

---

## Task 8: Settings tab

**Files:**
- Modify: `pkgs/uniremote/uniremote_gtk.py` — replace `SettingsTab` class

**Step 1: Replace SettingsTab**

Replace the `SettingsTab` class:

```python
class SettingsTab(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                         margin_top=12, margin_bottom=12, margin_start=12, margin_end=12)

        # --- Samsung section ---
        samsung_lbl = Gtk.Label(label="Samsung SmartThings", halign=Gtk.Align.START)
        samsung_lbl.add_css_class("heading")
        self.append(samsung_lbl)

        self.token_entry = Gtk.Entry(placeholder_text="API Token", visibility=False,
                                     text=config.samsung_token)
        self.append(self.token_entry)

        fetch_row = Gtk.Box(spacing=8)
        self.device_dropdown = Gtk.DropDown.new_from_strings(["(fetch devices first)"])
        self._device_ids: list[str] = []
        fetch_btn = Gtk.Button(label="Fetch Devices")
        fetch_btn.connect("clicked", self._on_fetch)
        fetch_row.append(self.device_dropdown)
        fetch_row.append(fetch_btn)
        self.append(fetch_row)

        # If device_id already saved, show it
        if config.samsung_device_id:
            self._device_ids = [config.samsung_device_id]
            self.device_dropdown.set_model(
                Gtk.StringList.new([f"Saved: {config.samsung_device_id}"])
            )

        # --- Roku section ---
        roku_lbl = Gtk.Label(label="Roku", halign=Gtk.Align.START)
        roku_lbl.add_css_class("heading")
        self.append(roku_lbl)

        roku_row = Gtk.Box(spacing=8)
        self.ip_entry = Gtk.Entry(placeholder_text="IP Address", text=config.roku_ip)
        discover_btn = Gtk.Button(label="Discover")
        discover_btn.connect("clicked", self._on_discover)
        roku_row.append(self.ip_entry)
        roku_row.append(discover_btn)
        self.append(roku_row)

        # --- Save ---
        save_btn = Gtk.Button(label="Save Settings")
        save_btn.add_css_class("suggested-action")
        save_btn.connect("clicked", self._on_save)
        self.append(save_btn)

        self.status_lbl = Gtk.Label(label="")
        self.append(self.status_lbl)

    def _on_fetch(self, _):
        token = self.token_entry.get_text().strip()
        if not token:
            self.status_lbl.set_text("Enter an API token first.")
            return
        self.status_lbl.set_text("Fetching devices…")
        run_async(SmartThingsAPI.fetch_devices, token, callback=self._on_devices_fetched)

    def _on_devices_fetched(self, result):
        if isinstance(result, Exception):
            self.status_lbl.set_text(f"Error: {result}")
            return
        if not result:
            self.status_lbl.set_text("No devices found.")
            return
        self._device_ids = [d[0] for d in result]
        names = [d[1] for d in result]
        self.device_dropdown.set_model(Gtk.StringList.new(names))
        self.status_lbl.set_text(f"Found {len(result)} device(s).")

    def _on_discover(self, _):
        self.status_lbl.set_text("Scanning for Roku…")
        run_async(discover_roku, callback=self._on_discovered)

    def _on_discovered(self, result):
        if isinstance(result, Exception) or not result:
            self.status_lbl.set_text("No Roku found on network.")
            return
        self.ip_entry.set_text(result)
        self.status_lbl.set_text(f"Found Roku at {result}")

    def _on_save(self, _):
        config.samsung_token = self.token_entry.get_text().strip()
        idx = self.device_dropdown.get_selected()
        if self._device_ids and idx < len(self._device_ids):
            config.samsung_device_id = self._device_ids[idx]
        config.roku_ip = self.ip_entry.get_text().strip()
        config.save()
        self.status_lbl.set_text("Settings saved.")
```

**Step 2: Smoke test**

```bash
python3 pkgs/uniremote/uniremote_gtk.py
```
Expected: Settings tab shows token field, Fetch Devices dropdown, Roku IP + Discover, Save button

**Step 3: Commit**

```bash
git add pkgs/uniremote/uniremote_gtk.py
git commit -m "feat(uniremote): add Settings tab with SmartThings fetch and Roku discover"
```

---

## Task 9: Update Nix package and flake

**Files:**
- Modify: `pkgs/uniremote/default.nix`
- Modify: `flake.nix`
- Modify: one of the profile nix files (desktop or surface, wherever the user runs this)

**Step 1: Update default.nix to install both Python files**

Replace `pkgs/uniremote/default.nix`:

```nix
{ lib, python3, python3Packages, gtk4, gobject-introspection, wrapGAppsHook }:

python3Packages.buildPythonApplication {
  pname = "uniremote";
  version = "0.1.0";

  src = ./.;
  format = "other";

  propagatedBuildInputs = with python3Packages; [
    pygobject3
    requests
  ];

  nativeBuildInputs = [
    wrapGAppsHook
    gobject-introspection
  ];

  buildInputs = [ gtk4 ];

  installPhase = ''
    mkdir -p $out/bin $out/${python3.sitePackages}
    cp uniremote_api.py $out/${python3.sitePackages}/uniremote_api.py
    install -m755 uniremote_gtk.py $out/bin/uniremote
  '';

  meta = with lib; {
    description = "GTK4 Roku/Samsung remote";
    platforms = platforms.linux;
  };
}
```

**Step 2: Add uniremote to flake overlay**

In `flake.nix`, update the `overlays.default` and `packages` sections:

```nix
overlays.default = final: prev: {
  sqlch = prev.callPackage ./pkgs/sqlch { };
  uniremote = prev.callPackage ./pkgs/uniremote { };
};
packages.${system} = {
  default = (pkgsFor system).sqlch;
  uniremote = (pkgsFor system).uniremote;
};
```

**Step 3: Add uniremote to desktop profile**

In the relevant profile (e.g., `profiles/home/desktop.nix` or `hosts/desktop/config.nix`), add:

```nix
environment.systemPackages = [ pkgs.uniremote ];
# or in home-manager:
home.packages = [ pkgs.uniremote ];
```

Check which file currently lists user packages for the desktop host and add it there.

**Step 4: Commit**

```bash
git add pkgs/uniremote/default.nix flake.nix <profile-file>
git commit -m "feat(uniremote): wire Nix package into flake overlay and desktop profile"
```

---

## Task 10: Nix build test

**Step 1: Build the uniremote package**

```bash
cd ~/nixos
nix build .#packages.x86_64-linux.uniremote
```
Expected: Build succeeds, `result/bin/uniremote` exists

**Step 2: Verify the binary runs**

```bash
./result/bin/uniremote
```
Expected: GTK4 window opens with 3 tabs

**Step 3: Run unit tests one final time**

```bash
python3 -m pytest pkgs/uniremote/tests/ -v
```
Expected: All tests PASSED

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat(uniremote): complete universal remote app for Samsung TV and Roku"
```
