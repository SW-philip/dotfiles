# Surface: Lix Migration + Two-Bar Waybar Split

Date: 2026-04-23

## Goals

1. Migrate the surface host from plain Nix to Lix (latest compatible with nixos-25.11)
2. Split the surface's single top Waybar into a top bar and a bottom bar

---

## Part 1: Lix Migration

### Approach

Add `lix-module` as a flake input and inject `lix-module.nixosModules.default` into the surface `nixosConfiguration` modules list. Lix replaces the Nix evaluator/daemon; nixpkgs, home-manager, and all other inputs remain unchanged.

The desktop host is untouched (it runs nixpkgs-unstable on a different cadence).

### Flake changes (`flake.nix`)

- Add input: `lix-module.url = "https://git.lix.systems/lix-project/lix-module/archive/main.tar.gz"`
- Add `lix-module.inputs.nixpkgs.follows = "nixpkgs"` to pin it to the surface's nixpkgs
- Add `lix-module` to the `outputs` args
- Add `lix-module.nixosModules.default` to the `surface` modules list

---

## Part 2: Two-Bar Waybar Layout

### Top Bar (`eDP-1`, position: top)

| Section | Modules |
|---------|---------|
| Left    | `hyprland/workspaces`, `custom/choose_mode` |
| Center  | *(empty)* |
| Right   | `custom/volume`, `custom/sqlch`, `custom/mpris` |

### Bottom Bar (`eDP-1`, position: bottom)

| Section | Modules |
|---------|---------|
| Left    | `custom/cpu_temp`, `custom/battery`, `custom/btrfs`, `custom/sleep_drain` |
| Center  | `custom/clock`, `custom/weather` |
| Right   | `group/connectivity`, `tray`, `custom/flake_drift`, `group/toggles` (drawer), `group/actions` (drawer) |

### Drawer Groups

**`group/toggles`** — handle: `custom/power_profile`, opens left, reveals `idle_inhibit`, `dnd`, `choose_mode`

**`group/actions`** — handle: `custom/wleave`, opens left, reveals `custom/uniremote`

Both drawers use `transition-duration = 500` and `transition-left-to-right = false`.

---

## Files to Change

- `flake.nix` — add lix-module input + surface module
- `home/waybar/default.nix` — replace surface `mainBar` with `surfaceTopBar` + `surfaceBottomBar`
