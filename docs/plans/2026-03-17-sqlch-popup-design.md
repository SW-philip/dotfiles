# sqlch-popup design
2026-03-17

## What

A GTK4 layer-shell popup triggered by left-clicking the sqlch widget in ironbar.
Replaces the current left-click `--pause` with a proper radio player panel.

## Why

sqlch is a full radio player (daemon, stations, ICY metadata, album art cache, Spotify enrichment) but the only UI is a one-liner in the bar and fuzzel for picking stations. A popup gives it a surface worth the underlying system.

## Approach

Standalone Python script using GTK4 + gtk4-layer-shell. No shell framework (ags/eww/ignis). Talks directly to the daemon Unix socket (`$XDG_RUNTIME_DIR/sqlch/control.sock`).

Chosen over ags/ignis because the scope is one popup, sqlch has a clean socket API, and a focused Python script is easier to debug and maintain.

## UI layout

```
┌─────────────────────────────┐
│ ◉ WXPN          [Local]     │  ← station name + category badge
│ Artist — Track name         │  ← ICY metadata (hidden if none)
│ [art]  ⏮  ⏸  ⏹  ⏭         │  ← album art thumbnail + controls
├─────────────────────────────┤
│ ▾ Local                     │  ← collapsible category group
│   WXPN          ●           │  ← active station dot
│   XPONENTIAL                │
│ ▾ Punk                      │
│   PUNKROCKDEMONSTRATION      │
│ ▾ Pop                        │
│   ADRNPOP                   │
│  ...                        │
└─────────────────────────────┘
```

Width: ~320px. Height: auto, capped with scroll on the station list.
Anchor: top edge, aligned to the right (where the sqlch widget sits in ironbar).

## Behavior

- **Toggle:** each left-click on the ironbar sqlch widget opens or closes the panel
- **Now playing:** polls daemon socket every 1.5s for status; updates station name, ICY track, art
- **Album art:** loaded from `~/.cache/sqlch/covers/` via the enriched.json lookup; falls back to a placeholder icon if none
- **Controls:** ⏮ ⏸/▶ ⏹ ⏭ send commands directly to daemon socket (no subprocess)
- **Station list:** populated from `sqlch list` output on open; grouped by category; clicking a row sends `{"cmd": "play", "query": id}`; active station highlighted

## Styling

Rosé Pine dark, matching ironbar:
- Background: `#191724` base with `#1f1d2e` surface
- Text: `#e0def4`, muted: `#6e6a86`
- Accent/active: `#c4a7e7` iris
- Border: `rgba(168,96,119,0.25)` rose
- Rounded corners: 12px on the window, 6px on rows
- CSS injected via `Gtk.CssProvider`

## Files to create/modify

- `home/niri/sqlch-popup` — new Python script (the popup itself)
- `home/niri/default.nix` — wire `sqlch-popup` into home packages + make it executable
- `home/niri/ironbar.toml` — change `on_click_left` on sqlch widgets from `--pause` to `sqlch-popup`

## Dependencies (already in nixos)

- `python3` with `pygobject3` (gi.repository.Gtk, Gio, GLib, GdkPixbuf)
- `gtk4-layer-shell` (gtk4-layer-shell python bindings or via gi typelib)
