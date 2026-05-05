# Design: Niri + Ironbar alongside Hyprland + Waybar

Date: 2026-03-13

## Goal

Add niri as a selectable Wayland session alongside Hyprland on both desktop and surface hosts. The user picks the compositor at login (tuigreet / GDM). Each compositor owns its own bar — no bar bleeds into the other's session.

## Session Isolation Mechanism

Hyprland and Niri each register a compositor-specific systemd user target:
- `hyprland-session.target`
- `niri-session.target`

Both extend `graphical-session.target`. By binding each bar to its compositor's target (instead of the generic `graphical-session.target`), the bars are naturally isolated — no exec.conf tricks needed.

## Changes

### System level — new `profiles/niri.nix`

Mirrors the existing `profiles/hyprland.nix`. Contains:
- `programs.niri.enable = true` — registers the niri session desktop file, activates `niri-session.target`
- Appropriate xdg-desktop-portal entries for niri
- Wayland session environment variables (shared with hyprland profile)

Import into both:
- `hosts/desktop/config.nix`
- `hosts/surface/config.nix`

### Home-manager — waybar target fix

In `home/waybar/default.nix`:
- Change `programs.waybar.systemd.targets` from the default `graphical-session.target` to `hyprland-session.target`

This prevents waybar from auto-starting inside niri sessions.

### Home-manager — new `home/niri/`

New directory, mirroring `home/hypr/`. Contains:
- `default.nix` — imports niri config + ironbar service
- Niri config file(s) — minimal "cleanroom" layout (scrollable tiling, no gaps distraction)
- `systemd.user.services.ironbar` — tied to `niri-session.target`, `WantedBy = ["niri-session.target"]`
- Basic ironbar config — clean, minimal bar suitable for focused work

### Home-manager — base profile

In `profiles/home/base.nix`:
- Add `../../home/niri` to the imports list alongside `../../home/waybar` and `../../home/mako`

## What Stays the Same

- `flake.nix` — no changes needed; both sessions appear in tuigreet/GDM automatically via session desktop files
- `home/hypr/` — no changes; exec.conf can remain but the systemd target handles startup
- `modules/greetd.nix` / `modules/gdm.nix` — no changes; both DMs read session desktop files from the same place

## Non-Goals

- No compositor toggle flag or NixOS option needed
- No separate flake outputs per compositor
- No changes to the surface display manager setup
