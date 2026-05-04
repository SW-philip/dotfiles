#!/usr/bin/env python3
"""
hypr-dash — Hyprland Configuration Dashboard
Requires: python3, pygobject (gtk4), hyprland running
NixOS: nix-shell -p python3 python3Packages.pygobject3 gtk4
"""

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib, Gdk, Gio, Pango
import subprocess
import json
import os
import re
import threading
import time

HYPR_CONF = os.path.expanduser("~/.config/hypr/hyprland.conf")

# ─── Helpers ────────────────────────────────────────────────────────────────

def hyprctl(*args):
    try:
        result = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=2)
        return result.stdout.strip()
    except Exception as e:
        return f"error: {e}"

def hyprctl_json(cmd):
    try:
        result = subprocess.run(["hyprctl", "-j", cmd], capture_output=True, text=True, timeout=2)
        return json.loads(result.stdout)
    except:
        return {}

def wpctl(*args):
    try:
        result = subprocess.run(["wpctl", *args], capture_output=True, text=True, timeout=2)
        return result.stdout.strip()
    except Exception as e:
        return f"error: {e}"

def read_conf():
    try:
        with open(HYPR_CONF, "r") as f:
            return f.read()
    except:
        return ""

def write_conf(content):
    with open(HYPR_CONF, "w") as f:
        f.write(content)

def set_conf_value(key, value):
    """Live-patch a single key=value in hyprland.conf and reload."""
    content = read_conf()
    # match key = anything (inside any block)
    pattern = rf"(\b{re.escape(key)}\s*=\s*)([^\n]+)"
    new_content = re.sub(pattern, rf"\g<1>{value}", content)
    if new_content == content:
        # key not found, append under general {}
        new_content += f"\n{key} = {value}\n"
    write_conf(new_content)
    hyprctl("reload")

def get_conf_value(key, default=""):
    content = read_conf()
    m = re.search(rf"\b{re.escape(key)}\s*=\s*([^\n]+)", content)
    if m:
        return m.group(1).strip()
    return default

def sysread(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except:
        return "0"

def cpu_percent():
    try:
        with open("/proc/stat") as f:
            line = f.readline()
        vals = list(map(int, line.split()[1:]))
        idle = vals[3]
        total = sum(vals)
        return total, idle
    except:
        return 0, 0

# ─── CSS ────────────────────────────────────────────────────────────────────

CSS = b"""
window {
  background-color: #0d0d0f;
  color: #e2e0dc;
  font-family: "JetBrains Mono", "Iosevka", monospace;
  font-size: 13px;
}

.sidebar {
  background-color: #111114;
  border-right: 1px solid #1e1e22;
  min-width: 160px;
}

.nav-btn {
  background: transparent;
  border: none;
  border-radius: 0;
  color: #666;
  font-family: "JetBrains Mono", monospace;
  font-size: 12px;
  padding: 12px 20px;
  text-align: left;
  letter-spacing: 0.08em;
  transition: all 120ms ease;
}

.nav-btn:hover {
  background-color: #1a1a1e;
  color: #c8c4be;
}

.nav-btn.active {
  background-color: #1e1e24;
  color: #f0c060;
  border-left: 2px solid #f0c060;
}

.page-title {
  font-size: 11px;
  font-weight: bold;
  letter-spacing: 0.15em;
  color: #f0c060;
  margin-bottom: 4px;
  text-transform: uppercase;
}

.section-label {
  font-size: 10px;
  letter-spacing: 0.12em;
  color: #444;
  text-transform: uppercase;
  margin-top: 20px;
  margin-bottom: 6px;
}

.card {
  background-color: #111114;
  border: 1px solid #1e1e22;
  border-radius: 6px;
  padding: 16px;
  margin-bottom: 10px;
}

.control-label {
  font-size: 12px;
  color: #888;
  min-width: 140px;
}

scale trough {
  background-color: #1e1e24;
  border-radius: 4px;
}

scale highlight {
  background-color: #f0c060;
  border-radius: 4px;
}

scale slider {
  background-color: #f0c060;
  border: none;
  border-radius: 50%;
  min-width: 14px;
  min-height: 14px;
}

entry {
  background-color: #0a0a0c;
  border: 1px solid #2a2a30;
  border-radius: 4px;
  color: #e2e0dc;
  font-family: "JetBrains Mono", monospace;
  padding: 6px 10px;
}

entry:focus {
  border-color: #f0c060;
}

button.apply-btn {
  background-color: #f0c060;
  color: #0d0d0f;
  border: none;
  border-radius: 4px;
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  font-weight: bold;
  letter-spacing: 0.05em;
  padding: 6px 14px;
}

button.apply-btn:hover {
  background-color: #ffd070;
}

button.danger-btn {
  background-color: transparent;
  border: 1px solid #c05050;
  color: #c05050;
  border-radius: 4px;
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  padding: 6px 14px;
}

button.danger-btn:hover {
  background-color: #c05050;
  color: #0d0d0f;
}

.stat-value {
  font-size: 22px;
  font-weight: bold;
  color: #f0c060;
  font-family: "JetBrains Mono", monospace;
}

.stat-label {
  font-size: 10px;
  color: #555;
  letter-spacing: 0.1em;
  text-transform: uppercase;
}

.sink-btn {
  background-color: #161618;
  border: 1px solid #2a2a30;
  border-radius: 4px;
  color: #888;
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  padding: 8px 14px;
  margin: 3px 0;
}

.sink-btn:hover {
  border-color: #f0c060;
  color: #e2e0dc;
}

.sink-btn.active-sink {
  border-color: #f0c060;
  color: #f0c060;
  background-color: #1a1a14;
}

.keybind-key {
  background-color: #1a1a1e;
  border: 1px solid #2a2a30;
  border-radius: 3px;
  color: #f0c060;
  font-family: "JetBrains Mono", monospace;
  font-size: 11px;
  padding: 2px 7px;
  margin-right: 4px;
}

.keybind-desc {
  color: #888;
  font-size: 12px;
}

.status-bar {
  background-color: #0a0a0c;
  border-top: 1px solid #1e1e22;
  padding: 4px 16px;
  font-size: 11px;
  color: #444;
}

colorbutton {
  border-radius: 4px;
  min-width: 40px;
  min-height: 28px;
}
"""

# ─── Pages ──────────────────────────────────────────────────────────────────

class AppearancePage(Gtk.Box):
    def __init__(self, status_cb):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.status_cb = status_cb
        self.set_margin_top(24)
        self.set_margin_bottom(24)
        self.set_margin_start(28)
        self.set_margin_end(28)

        title = Gtk.Label(label="APPEARANCE")
        title.add_css_class("page-title")
        title.set_halign(Gtk.Align.START)
        self.append(title)

        subtitle = Gtk.Label(label="Live edits reload hyprland.conf instantly")
        subtitle.add_css_class("section-label")
        subtitle.set_halign(Gtk.Align.START)
        self.append(subtitle)

        # ── Borders card
        self._add_section("BORDERS & ROUNDING")
        borders = self._card()

        self.border_w = self._slider_row(borders, "border_size", 0, 10, 1,
                                          float(get_conf_value("border_size", "2")))
        self.rounding = self._slider_row(borders, "rounding", 0, 20, 1,
                                          float(get_conf_value("rounding", "8")))
        self.gaps_in = self._slider_row(borders, "gaps_in", 0, 30, 1,
                                         float(get_conf_value("gaps_in", "5")))
        self.gaps_out = self._slider_row(borders, "gaps_out", 0, 60, 1,
                                          float(get_conf_value("gaps_out", "20")))
        self.append(borders)

        # ── Colors card
        self._add_section("COLORS")
        colors = self._card()

        self.col_active = self._color_row(colors, "col.active_border",
                                           get_conf_value("col.active_border", "rgba(f0c060ff)"))
        self.col_inactive = self._color_row(colors, "col.inactive_border",
                                             get_conf_value("col.inactive_border", "rgba(1e1e22ff)"))
        self.col_group = self._color_row(colors, "col.group_border_active",
                                          get_conf_value("col.group_border_active", "rgba(60a0f0ff)"))
        self.append(colors)

        # ── Opacity card
        self._add_section("OPACITY & BLUR")
        opacity = self._card()

        self.active_op = self._slider_row(opacity, "active_opacity", 0.5, 1.0, 0.01,
                                           float(get_conf_value("active_opacity", "1.0")))
        self.inactive_op = self._slider_row(opacity, "inactive_opacity", 0.5, 1.0, 0.01,
                                             float(get_conf_value("inactive_opacity", "0.95")))
        self.blur_size = self._slider_row(opacity, "blur_size", 1, 20, 1,
                                           float(get_conf_value("blur_size", "8")))
        self.blur_passes = self._slider_row(opacity, "blur_passes", 1, 5, 1,
                                             float(get_conf_value("blur_passes", "2")))
        self.append(opacity)

        # ── Animation card
        self._add_section("ANIMATIONS")
        anim = self._card()
        self.anim_speed = self._slider_row(anim, "animation speed", 1, 10, 0.5,
                                            self._get_anim_speed())
        apply_anim = Gtk.Button(label="APPLY SPEED")
        apply_anim.add_css_class("apply-btn")
        apply_anim.connect("clicked", self._apply_anim_speed)
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        row.set_halign(Gtk.Align.END)
        row.append(apply_anim)
        anim.append(row)
        self.append(anim)

    def _get_anim_speed(self):
        content = read_conf()
        m = re.search(r"animation\s*=\s*\w+\s*,\s*\d+\s*,\s*([\d.]+)", content)
        return float(m.group(1)) if m else 3.0

    def _apply_anim_speed(self, btn):
        speed = self.anim_speed.get_value()
        content = read_conf()
        new = re.sub(r"(animation\s*=\s*\w+\s*,\s*\d+\s*,\s*)([\d.]+)",
                     lambda m: m.group(1) + str(speed), content)
        write_conf(new)
        hyprctl("reload")
        self.status_cb(f"animation speed → {speed}")

    def _add_section(self, text):
        lbl = Gtk.Label(label=text)
        lbl.add_css_class("section-label")
        lbl.set_halign(Gtk.Align.START)
        self.append(lbl)

    def _card(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.add_css_class("card")
        return box

    def _slider_row(self, parent, key, mn, mx, step, value):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row.set_valign(Gtk.Align.CENTER)

        lbl = Gtk.Label(label=key)
        lbl.add_css_class("control-label")
        lbl.set_halign(Gtk.Align.START)

        adj = Gtk.Adjustment(value=value, lower=mn, upper=mx, step_increment=step)
        scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=adj)
        scale.set_hexpand(True)
        scale.set_draw_value(True)
        scale.set_digits(2 if step < 1 else 0)

        val_lbl = Gtk.Label(label=str(value))
        val_lbl.set_width_chars(5)

        def on_change(s):
            v = s.get_value()
            val_lbl.set_label(f"{v:.2f}" if step < 1 else f"{int(v)}")
            set_conf_value(key, f"{v:.2f}" if step < 1 else f"{int(v)}")
            self.status_cb(f"{key} → {v:.2f}" if step < 1 else f"{key} → {int(v)}")

        scale.connect("value-changed", on_change)

        row.append(lbl)
        row.append(scale)
        row.append(val_lbl)
        parent.append(row)
        return scale

    def _color_row(self, parent, key, current):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row.set_valign(Gtk.Align.CENTER)

        lbl = Gtk.Label(label=key)
        lbl.add_css_class("control-label")
        lbl.set_halign(Gtk.Align.START)

        entry = Gtk.Entry()
        entry.set_text(current)
        entry.set_hexpand(True)
        entry.set_placeholder_text("rgba(rrggbbaa) or 0xrrggbbaa")

        apply = Gtk.Button(label="SET")
        apply.add_css_class("apply-btn")

        def on_apply(btn):
            val = entry.get_text().strip()
            set_conf_value(key, val)
            self.status_cb(f"{key} → {val}")

        apply.connect("clicked", on_apply)
        entry.connect("activate", on_apply)

        row.append(lbl)
        row.append(entry)
        row.append(apply)
        parent.append(row)
        return entry


class AudioPage(Gtk.Box):
    def __init__(self, status_cb):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.status_cb = status_cb
        self.set_margin_top(24)
        self.set_margin_bottom(24)
        self.set_margin_start(28)
        self.set_margin_end(28)

        title = Gtk.Label(label="AUDIO")
        title.add_css_class("page-title")
        title.set_halign(Gtk.Align.START)
        self.append(title)

        self._add_section("OUTPUT SINKS")
        self.sinks_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.sinks_box.add_css_class("card")
        self.append(self.sinks_box)

        self._add_section("VOLUME")
        vol_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        vol_card.add_css_class("card")

        vol_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        vol_lbl = Gtk.Label(label="output volume")
        vol_lbl.add_css_class("control-label")

        self.vol_adj = Gtk.Adjustment(value=1.0, lower=0.0, upper=1.5, step_increment=0.01)
        self.vol_scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=self.vol_adj)
        self.vol_scale.set_hexpand(True)
        self.vol_scale.set_draw_value(True)
        self.vol_scale.set_digits(2)
        self.vol_scale.connect("value-changed", self._on_volume)

        mute_btn = Gtk.Button(label="MUTE")
        mute_btn.add_css_class("danger-btn")
        mute_btn.connect("clicked", self._on_mute)

        vol_row.append(vol_lbl)
        vol_row.append(self.vol_scale)
        vol_row.append(mute_btn)
        vol_card.append(vol_row)
        self.append(vol_card)

        self._add_section("INPUT SOURCES")
        self.sources_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.sources_box.add_css_class("card")
        self.append(self.sources_box)

        self.refresh_btn = Gtk.Button(label="REFRESH DEVICES")
        self.refresh_btn.add_css_class("apply-btn")
        self.refresh_btn.set_halign(Gtk.Align.START)
        self.refresh_btn.set_margin_top(8)
        self.refresh_btn.connect("clicked", lambda _: self.refresh())
        self.append(self.refresh_btn)

        self.refresh()

    def _add_section(self, text):
        lbl = Gtk.Label(label=text)
        lbl.add_css_class("section-label")
        lbl.set_halign(Gtk.Align.START)
        self.append(lbl)

    def refresh(self):
        # clear
        while self.sinks_box.get_first_child():
            self.sinks_box.remove(self.sinks_box.get_first_child())
        while self.sources_box.get_first_child():
            self.sources_box.remove(self.sources_box.get_first_child())

        raw = wpctl("status")
        self._parse_and_build(raw)
        self._update_volume()

    def _parse_and_build(self, raw):
        in_sinks = False
        in_sources = False
        sink_pattern = re.compile(r"[│\s]+(\*?)\s+(\d+)\.\s+(.+?)\s+\[vol: ([\d.]+)(.*?)\]")

        for line in raw.splitlines():
            if "Sinks:" in line:
                in_sinks = True
                in_sources = False
                continue
            if "Sources:" in line:
                in_sinks = False
                in_sources = True
                continue
            if "Filters:" in line or "Streams:" in line:
                in_sinks = False
                in_sources = False

            m = sink_pattern.search(line)
            if m and (in_sinks or in_sources):
                is_default = bool(m.group(1).strip())
                sink_id = m.group(2)
                name = m.group(3).strip()
                muted = "MUTED" in m.group(5)

                btn = Gtk.Button()
                btn.add_css_class("sink-btn")
                if is_default:
                    btn.add_css_class("active-sink")

                label_text = f"{'▶ ' if is_default else '  '}{sink_id}  {name}"
                if muted:
                    label_text += "  [MUTED]"
                btn.set_label(label_text)
                btn.connect("clicked", self._set_sink, sink_id)

                if in_sinks:
                    self.sinks_box.append(btn)
                else:
                    self.sources_box.append(btn)

    def _set_sink(self, btn, sink_id):
        wpctl("set-default", sink_id)
        self.status_cb(f"default sink → {sink_id}")
        GLib.timeout_add(300, self.refresh)

    def _on_volume(self, scale):
        v = scale.get_value()
        wpctl("set-volume", "@DEFAULT_AUDIO_SINK@", f"{v:.2f}")

    def _on_mute(self, btn):
        wpctl("set-mute", "@DEFAULT_AUDIO_SINK@", "toggle")
        self.status_cb("toggled mute")
        GLib.timeout_add(200, self._update_volume)

    def _update_volume(self):
        raw = wpctl("get-volume", "@DEFAULT_AUDIO_SINK@")
        m = re.search(r"Volume:\s*([\d.]+)", raw)
        if m:
            self.vol_adj.set_value(float(m.group(1)))


class SystemPage(Gtk.Box):
    def __init__(self, status_cb):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.status_cb = status_cb
        self._prev_cpu = cpu_percent()

        self.set_margin_top(24)
        self.set_margin_bottom(24)
        self.set_margin_start(28)
        self.set_margin_end(28)

        title = Gtk.Label(label="SYSTEM")
        title.add_css_class("page-title")
        title.set_halign(Gtk.Align.START)
        self.append(title)

        lbl = Gtk.Label(label="LIVE STATS")
        lbl.add_css_class("section-label")
        lbl.set_halign(Gtk.Align.START)
        self.append(lbl)

        stats_card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        stats_card.add_css_class("card")
        stats_card.set_homogeneous(True)

        self.cpu_val, _ = self._stat_widget(stats_card, "CPU", "%")
        self.mem_val, _ = self._stat_widget(stats_card, "RAM", "MB")
        self.swap_val, _ = self._stat_widget(stats_card, "SWAP", "MB")
        self.append(stats_card)

        # Hyprland info
        lbl2 = Gtk.Label(label="HYPRLAND")
        lbl2.add_css_class("section-label")
        lbl2.set_halign(Gtk.Align.START)
        self.append(lbl2)

        hypr_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        hypr_card.add_css_class("card")

        self.hypr_version = self._info_row(hypr_card, "version")
        self.hypr_monitors = self._info_row(hypr_card, "monitors")
        self.hypr_workspaces = self._info_row(hypr_card, "workspaces")
        self.hypr_clients = self._info_row(hypr_card, "clients")
        self.append(hypr_card)

        # Quick actions
        lbl3 = Gtk.Label(label="ACTIONS")
        lbl3.add_css_class("section-label")
        lbl3.set_halign(Gtk.Align.START)
        self.append(lbl3)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        for label, cmd in [
            ("RELOAD", ["hyprctl", "reload"]),
            ("KILL ACTIVE", ["hyprctl", "dispatch", "killactive"]),
            ("FULLSCREEN", ["hyprctl", "dispatch", "fullscreen"]),
        ]:
            btn = Gtk.Button(label=label)
            btn.add_css_class("apply-btn" if label == "RELOAD" else "danger-btn")
            btn.connect("clicked", self._run_cmd, cmd)
            actions.append(btn)
        self.append(actions)

        GLib.timeout_add(1500, self._tick)
        self._tick()

    def _run_cmd(self, btn, cmd):
        subprocess.Popen(cmd)
        self.status_cb(f"ran: {' '.join(cmd)}")

    def _stat_widget(self, parent, name, unit):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_halign(Gtk.Align.CENTER)
        box.set_valign(Gtk.Align.CENTER)

        val = Gtk.Label(label="—")
        val.add_css_class("stat-value")

        lbl = Gtk.Label(label=f"{name} ({unit})")
        lbl.add_css_class("stat-label")

        box.append(val)
        box.append(lbl)
        parent.append(box)
        return val, lbl

    def _info_row(self, parent, key):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        lbl = Gtk.Label(label=key)
        lbl.add_css_class("control-label")
        val = Gtk.Label(label="—")
        val.add_css_class("keybind-desc")
        val.set_halign(Gtk.Align.START)
        row.append(lbl)
        row.append(val)
        parent.append(row)
        return val

    def _tick(self):
        # CPU
        total, idle = cpu_percent()
        pt, pi = self._prev_cpu
        dt = total - pt
        di = idle - pi
        pct = 100.0 * (dt - di) / dt if dt > 0 else 0
        self._prev_cpu = (total, idle)
        self.cpu_val.set_label(f"{pct:.1f}")

        # Memory
        try:
            with open("/proc/meminfo") as f:
                lines = f.readlines()
            mem = {}
            for l in lines:
                parts = l.split()
                if len(parts) >= 2:
                    mem[parts[0].rstrip(":")] = int(parts[1])
            total_mb = mem.get("MemTotal", 0) // 1024
            avail_mb = mem.get("MemAvailable", 0) // 1024
            used_mb = total_mb - avail_mb
            self.mem_val.set_label(f"{used_mb}")
            swap_total = mem.get("SwapTotal", 0) // 1024
            swap_free = mem.get("SwapFree", 0) // 1024
            self.swap_val.set_label(f"{swap_total - swap_free}")
        except:
            pass

        # Hyprland
        version = hyprctl("version")
        self.hypr_version.set_label(version.split("\n")[0][:60] if version else "not running")

        monitors = hyprctl_json("monitors")
        self.hypr_monitors.set_label(f"{len(monitors)} connected" if monitors else "—")

        workspaces = hyprctl_json("workspaces")
        self.hypr_workspaces.set_label(f"{len(workspaces)} active" if workspaces else "—")

        clients = hyprctl_json("clients")
        self.hypr_clients.set_label(f"{len(clients)} windows" if clients else "—")

        return True  # keep ticking


class KeybindsPage(Gtk.ScrolledWindow):
    def __init__(self, status_cb):
        super().__init__()
        self.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.set_margin_top(24)
        box.set_margin_bottom(24)
        box.set_margin_start(28)
        box.set_margin_end(28)

        title = Gtk.Label(label="KEYBINDS")
        title.add_css_class("page-title")
        title.set_halign(Gtk.Align.START)
        box.append(title)

        lbl = Gtk.Label(label="from hyprland.conf  ·  bind = MOD, key, dispatcher, arg")
        lbl.add_css_class("section-label")
        lbl.set_halign(Gtk.Align.START)
        box.append(lbl)

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        card.add_css_class("card")

        binds = self._parse_binds()
        if not binds:
            empty = Gtk.Label(label="no binds found in hyprland.conf")
            empty.add_css_class("keybind-desc")
            card.append(empty)
        else:
            for mod, key, dispatcher, arg in binds:
                row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
                row.set_valign(Gtk.Align.CENTER)

                for k in [mod, key]:
                    if k:
                        klbl = Gtk.Label(label=k.upper())
                        klbl.add_css_class("keybind-key")
                        row.append(klbl)

                sep = Gtk.Label(label="→")
                sep.add_css_class("section-label")
                row.append(sep)

                desc = Gtk.Label(label=f"{dispatcher}  {arg}".strip())
                desc.add_css_class("keybind-desc")
                desc.set_halign(Gtk.Align.START)
                desc.set_ellipsize(Pango.EllipsizeMode.END)
                row.append(desc)

                card.append(row)

        box.append(card)
        self.set_child(box)

    def _parse_binds(self):
        content = read_conf()
        binds = []
        for line in content.splitlines():
            line = line.strip()
            m = re.match(r"bind\w*\s*=\s*([^,]*),\s*([^,]*),\s*([^,]*),?(.*)", line)
            if m:
                binds.append((m.group(1).strip(), m.group(2).strip(),
                               m.group(3).strip(), m.group(4).strip()))
        return binds


class RawConfigPage(Gtk.Box):
    def __init__(self, status_cb):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.status_cb = status_cb

        self.set_margin_top(24)
        self.set_margin_bottom(24)
        self.set_margin_start(28)
        self.set_margin_end(28)

        title = Gtk.Label(label="RAW CONFIG")
        title.add_css_class("page-title")
        title.set_halign(Gtk.Align.START)
        self.append(title)

        lbl = Gtk.Label(label=HYPR_CONF)
        lbl.add_css_class("section-label")
        lbl.set_halign(Gtk.Align.START)
        self.append(lbl)

        sw = Gtk.ScrolledWindow()
        sw.set_vexpand(True)
        sw.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)

        self.textview = Gtk.TextView()
        self.textview.set_monospace(True)
        self.textview.set_left_margin(12)
        self.textview.set_right_margin(12)
        self.textview.set_top_margin(12)
        self.textview.set_bottom_margin(12)
        self.textview.get_buffer().set_text(read_conf())
        sw.set_child(self.textview)
        self.append(sw)

        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_row.set_margin_top(12)

        save = Gtk.Button(label="SAVE & RELOAD")
        save.add_css_class("apply-btn")
        save.connect("clicked", self._save)

        reload_only = Gtk.Button(label="RELOAD ONLY")
        reload_only.add_css_class("apply-btn")
        reload_only.connect("clicked", lambda _: hyprctl("reload"))

        discard = Gtk.Button(label="DISCARD")
        discard.add_css_class("danger-btn")
        discard.connect("clicked", self._discard)

        btn_row.append(save)
        btn_row.append(reload_only)
        btn_row.append(discard)
        self.append(btn_row)

    def _save(self, btn):
        buf = self.textview.get_buffer()
        text = buf.get_text(buf.get_start_iter(), buf.get_end_iter(), True)
        write_conf(text)
        hyprctl("reload")
        self.status_cb("config saved & reloaded")

    def _discard(self, btn):
        self.textview.get_buffer().set_text(read_conf())
        self.status_cb("discarded changes")


# ─── Main Window ────────────────────────────────────────────────────────────

class HyprDash(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="hypr-dash")
        self.set_default_size(960, 680)

        # Apply CSS
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_content(outer)

        main = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        main.set_vexpand(True)
        outer.append(main)

        # Status bar
        self.status_bar = Gtk.Label(label="hypr-dash ready")
        self.status_bar.add_css_class("status-bar")
        self.status_bar.set_halign(Gtk.Align.START)
        outer.append(self.status_bar)

        # Sidebar
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        sidebar.add_css_class("sidebar")
        sidebar.set_valign(Gtk.Align.FILL)
        main.append(sidebar)

        logo = Gtk.Label(label="◈ hypr-dash")
        logo.set_margin_top(20)
        logo.set_margin_bottom(20)
        logo.set_margin_start(20)
        logo.add_css_class("page-title")
        logo.set_halign(Gtk.Align.START)
        sidebar.append(logo)

        sep = Gtk.Separator()
        sidebar.append(sep)

        # Content stack
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.stack.set_transition_duration(120)
        self.stack.set_vexpand(True)
        self.stack.set_hexpand(True)

        sw_appearance = Gtk.ScrolledWindow()
        sw_appearance.set_child(AppearancePage(self.set_status))
        sw_appearance.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        pages = [
            ("appearance", "APPEARANCE", sw_appearance),
            ("audio",      "AUDIO",      AudioPage(self.set_status)),
            ("system",     "SYSTEM",     SystemPage(self.set_status)),
            ("keybinds",   "KEYBINDS",   KeybindsPage(self.set_status)),
            ("config",     "RAW CONFIG", RawConfigPage(self.set_status)),
        ]

        self.nav_buttons = {}
        first = True
        for name, label, widget in pages:
            self.stack.add_named(widget, name)
            btn = Gtk.Button(label=label)
            btn.add_css_class("nav-btn")
            if first:
                btn.add_css_class("active")
                first = False
            btn.set_halign(Gtk.Align.FILL)
            btn.connect("clicked", self._nav, name)
            sidebar.append(btn)
            self.nav_buttons[name] = btn

        main.append(self.stack)

    def _nav(self, btn, name):
        self.stack.set_visible_child_name(name)
        for n, b in self.nav_buttons.items():
            if n == name:
                b.add_css_class("active")
            else:
                b.remove_css_class("active")

    def set_status(self, msg):
        self.status_bar.set_label(f"  {msg}")
        GLib.timeout_add(4000, lambda: self.status_bar.set_label("  ready"))


class HyprDashApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="com.hypr.dash",
                         flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.connect("activate", self.on_activate)

    def on_activate(self, app):
        win = HyprDash(app)
        win.present()


if __name__ == "__main__":
    import sys
    app = HyprDashApp()
    sys.exit(app.run(sys.argv))
