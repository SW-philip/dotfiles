#!/usr/bin/env python3
# pkgs/uniremote/uniremote_gtk.py
import sys
import threading
import gi
gi.require_version("Gtk", "4.0")
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
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=8,
                         margin_top=12, margin_bottom=12, margin_start=12, margin_end=12)
        self.add_css_class("samsung-tab")
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


def main():
    app = UniremoteApp()
    sys.exit(app.run(sys.argv))


if __name__ == "__main__":
    main()
