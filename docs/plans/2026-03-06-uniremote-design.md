# Uniremote Design — 2026-03-06

Universal remote GTK4 app for Samsung TV (via SmartThings) and Roku.

## Stack

- Language: Python 3
- UI: GTK4 via PyGObject (`Gtk.ApplicationWindow`, `Gtk.Notebook`)
- HTTP: `requests` library (non-blocking via background threads + `GLib.idle_add`)
- Config: `~/.config/uniremote/config.toml`
- Nix package: `pkgs/uniremote/default.nix` (already exists, installs `uniremote_gtk.py`)

## Config Format

```toml
[samsung]
token = ""
device_id = ""

[roku]
ip = ""
```

Auto-created with empty defaults on first run.

## UI: Three-tab Notebook

### Tab 1 — Samsung

Controls:
- Power toggle (top)
- D-pad: Up / Down / Left / Right / OK (center)
- Back, Home
- Volume Up / Down
- Channel Up / Down

API: SmartThings REST — `POST https://api.smartthings.com/v1/devices/{id}/commands`
Auth: `Authorization: Bearer <token>`

| Button | Capability | Command |
|--------|-----------|---------|
| Power on/off | `switch` | `on` / `off` |
| Vol+ / Vol- | `audioVolume` | `volumeUp` / `volumeDown` |
| Ch+ / Ch- | `tvChannel` | `channelUp` / `channelDown` |
| Up/Down/Left/Right/OK/Back/Home | `samsungvd.remoteControl` | `sendKey` + `KEY_UP` etc. |

### Tab 2 — Roku

Controls:
- Power
- D-pad: Up / Down / Left / Right / OK
- Back, Home
- Rewind, Play/Pause, Fast-forward
- Volume Down / Mute / Volume Up
- Search button (opens dialog with text entry)
- Scrollable installed apps grid (click to launch)

API: Roku ECP — `http://{ip}:8060`

| Action | Request |
|--------|---------|
| Key press | `POST /keypress/{key}` |
| List apps | `GET /query/apps` (parse XML) |
| Launch app | `POST /launch/{app_id}` |
| Search | `POST /search/browse?keyword={q}&launch=true` |

Roku key names: Up, Down, Left, Right, Select, Back, Home, Play, Rev, Fwd, VolumeUp, VolumeDown, VolumeMute, PowerOff, Search

App list loaded on tab switch. Search opens a `Gtk.Dialog` with text entry; Enter submits.

### Tab 3 — Settings

Layout:
```
--- Samsung SmartThings ---
API Token:  [field, password-masked]  [Fetch Devices]
Device:     [dropdown populated after fetch]

--- Roku ---
IP Address: [field]  [Discover]

[Save Settings]
```

Behaviors:
- **Fetch Devices**: calls `GET /v1/devices` with token, filters by `category=Television`, populates device dropdown. Saves selected device ID on Save.
- **Discover**: SSDP M-SEARCH multicast to `239.255.255.250:1900`, filter `roku:ecp` responses, extract IP from `Location:` header. 3-second timeout, runs in thread, shows spinner during scan.
- **Save**: writes all fields to config.toml, reloads in-memory config (no restart needed), shows success toast.

## Data Flow

1. App start: read config.toml (create defaults if missing), pre-fill Settings fields
2. Samsung button press: serialize SmartThings command, POST in background thread
3. Roku tab opened: fetch `/query/apps`, render scrollable app grid
4. Roku button press: POST to ECP in background thread
5. Search: dialog text entry -> POST `/search/browse` in background thread
6. Settings save: write toml, reload config

## Nix Integration

The package is already defined in `pkgs/uniremote/default.nix`. After writing the source:
- Add `uniremote` to the flake overlay alongside `sqlch`
- Add to the relevant home/desktop profile's packages

## Files to Create/Modify

- `pkgs/uniremote/uniremote_gtk.py` — main application (create)
- `flake.nix` — add uniremote to overlay (modify)
- Relevant profile `.nix` file — add uniremote to packages (modify)
