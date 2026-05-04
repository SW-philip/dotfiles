# Package Cleanup & Reorganization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove dead-weight packages, move user tools from systemPackages to home.packages, and fix cross-compositor inconsistencies — getting the repo clean for public GitHub.

**Architecture:** NixOS flake repo with two hosts (desktop/surface). System packages are in `profiles/base.nix` and `profiles/desktop.nix`. Home-manager packages live in `profiles/home/base.nix`. Changes flow: trim system → move to home → delete dead weight.

**Tech Stack:** NixOS flakes, home-manager (NixOS-integrated), Hyprland + Niri Wayland compositors, WirePlumber audio

---

## Decisions Locked In (do not re-litigate)

| Package | Decision | Reason |
|---|---|---|
| `pamixer` | Remove (after updating niri binds) | niri uses pamixer; Hyprland uses wpctl. Unify on wpctl. |
| `pulseaudio` | Remove | Violates wpctl-only rule. Nothing calls pactl. |
| `hyprpaper` | Remove | exec.conf uses `swww-daemon`, not hyprpaper. Dead weight. |
| `wofi` | Remove | `programs.wofi.enable` set but neither compositor calls it. fuzzel is used. |
| `swayosd` | Remove | In systemPackages but no bind/exec calls it anywhere. |
| `wf-recorder` | Remove | Duplicate of `wl-screenrec`. wl-screenrec is GPU-accelerated. |
| `wl-clipboard-rs` | Remove | `wl-clipboard` already in home.packages; binds.conf calls `wl-copy`. |
| `satty` | Remove | `swappy` already in home.packages. Both are annotation tools. |
| `libnatpmp` | Remove | No clear usage. |
| `dart-sass` | Remove | No SCSS pipeline in the codebase. |
| `wev` | Remove | Debug tool, use `nix shell nixpkgs#wev` on demand. |
| `socat` | Remove | Not referenced anywhere, use `nix shell` on demand. |
| `tree` | Remove | `eza --tree` aliased as `lt`/`ltt`. |
| `font-misc-misc`, `font-cursor-misc` | Remove | Legacy X11 bitmap fonts, Wayland-primary system. |
| `libinput` | Remove | Provided as a dep of Hyprland/Niri; diagnostic use `nix shell`. |
| `pinentry-qt` | Replace with gpg-agent | Qt pinentry is wrong for Wayland/GNOME session. |
| `wl-screenrec` | Move to home.packages | User tool, not system. |
| `ydotool` | Move to home.packages | User tool, not system. |
| `pythonEnv` | Move to home.packages | Personal dev env. Should not be system-wide. |
| `git neovim wget rsync jq ripgrep fd bat gitleaks age sops claude-code unzip` | Move to home.packages | Developer/user tools, not system utilities. |
| `swww fuzzel ghostty playerctl brightnessctl` | Keep in home.packages | Actively used by both compositors. |
| `curl pciutils usbutils sbctl sysstat lm_sensors` | Keep in systemPackages | Genuine system utilities. |
| `adw-gtk3` in family | Remove from home.packages | Already pulled in by `gtk.theme.package`. |
| `foliate` + `koreader` in surface | Keep both | User can decide at their own pace; both work. |

---

## Task 1: Update niri volume binds to use wpctl

**Files:**
- Modify: `home/niri/config.kdl.nix:192-194`

The niri volume keybinds call `pamixer`. Hyprland uses `wpctl`. Unify on `wpctl` so pamixer can be removed.

**Step 1: Edit the three volume lines in `home/niri/config.kdl.nix`**

Replace (lines ~192–194):
```
XF86AudioRaiseVolume  allow-when-locked=true { spawn "pamixer" "--increase" "5"; }
XF86AudioLowerVolume  allow-when-locked=true { spawn "pamixer" "--decrease" "5"; }
XF86AudioMute         allow-when-locked=true { spawn "pamixer" "--toggle-mute"; }
```
With:
```
XF86AudioRaiseVolume  allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
XF86AudioLowerVolume  allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
XF86AudioMute         allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
```

**Step 2: Commit**
```bash
git add home/niri/config.kdl.nix
git commit -m "niri: switch volume keys from pamixer to wpctl"
```

---

## Task 2: Trim systemPackages in profiles/base.nix

**Files:**
- Modify: `profiles/base.nix`

Remove dead weight and move developer tools out. These tools will land in `home.packages` in Task 4.

**Step 1: Edit `environment.systemPackages` in `profiles/base.nix`**

Replace the entire `environment.systemPackages` block:
```nix
environment.systemPackages = with pkgs; [
  curl
  pciutils
  usbutils
  sbctl
  sysstat
  lm_sensors
];
```

Removed from here: `git neovim wget tree rsync jq ripgrep fd bat gitleaks age sops pythonEnv claude-code unzip font-misc-misc font-cursor-misc libinput brightnessctl`

Keep `brightnessctl` — it IS called by both compositor configs (Hyprland binds.conf and niri config.kdl.nix). Add it back to the block:
```nix
environment.systemPackages = with pkgs; [
  curl
  pciutils
  usbutils
  sbctl
  sysstat
  lm_sensors
  brightnessctl
];
```

**Step 2: Move the pythonEnv `let` block**

The `let pythonEnv = ...` at the top of base.nix belongs in home-manager. Remove it from `profiles/base.nix` entirely (the `let...in` wrapper and the binding). It will be recreated in Task 3.

The file will open with `{ config, pkgs, lib, ... }:` followed directly by `{`.

**Step 3: Commit**
```bash
git add profiles/base.nix
git commit -m "system: trim systemPackages — move dev tools to home-manager"
```

---

## Task 3: Trim systemPackages in profiles/desktop.nix

**Files:**
- Modify: `profiles/desktop.nix`

**Step 1: Edit `environment.systemPackages` in `profiles/desktop.nix`**

Replace the block with:
```nix
environment.systemPackages = with pkgs; [
  # Wayland / screen tools
  wayland-utils
  wl-screenrec
  swayosd
  ydotool

  # Graphics diagnostics
  vulkan-tools
  mesa-demos

  # Hardware / sensors
  smartmontools
];
```

Removed: `wf-recorder` (dupe of wl-screenrec), `wl-clipboard-rs` (wl-clipboard already in home), `satty` (swappy already in home), `libnatpmp` (unused), `gnupg` (moving to home), `pinentry-qt` (replacing with gpg-agent setup)

Note: `swayosd` and `ydotool` stay in systemPackages for now — they need udev rules / device access that may require system-level installation. They can be audited further after the refactor.

**Step 2: Commit**
```bash
git add profiles/desktop.nix
git commit -m "system/desktop: remove dead weight and duplicate packages"
```

---

## Task 4: Add GPG setup to home-manager

**Files:**
- Modify: `profiles/home/base.nix`

Replace the bare `gnupg` + `pinentry-qt` system packages with a proper home-manager gpg-agent setup.

**Step 1: Add to the `programs` block in `profiles/home/base.nix`**

Add after `programs.firefox.enable = true;`:
```nix
gpg.enable = true;
```

**Step 2: Add gpg-agent service to `profiles/home/base.nix`**

Add a new section after the `services` block (or alongside `services.hypridle`):
```nix
services.gpg-agent = {
  enable = true;
  pinentryPackage = pkgs.pinentry-gnome3;
};
```

**Step 3: Commit**
```bash
git add profiles/home/base.nix
git commit -m "home: add programs.gpg + services.gpg-agent (replaces system gnupg)"
```

---

## Task 5: Add pythonEnv to home-manager and clean home.packages

**Files:**
- Modify: `profiles/home/base.nix`

**Step 1: Add the pythonEnv let-binding at the top of `profiles/home/base.nix`**

The file currently opens with:
```nix
# profiles/home/base.nix
{ inputs, pkgs, lib, config, ... }:
{
```

Change to:
```nix
# profiles/home/base.nix
{ inputs, pkgs, lib, config, ... }:
let
  pythonEnv = pkgs.python312.withPackages (ps: with ps; [
    # UI / TUI
    pygobject3 textual rich pystray pillow pydbus cairosvg
    # Networking / data
    requests watchdog python-dateutil
    # Infra / logging
    loguru platformdirs attrs typing-extensions
    # Build tooling
    build setuptools wheel
  ]);
in
{
```

**Step 2: Replace `home.packages` in `profiles/home/base.nix`**

Replace the entire `home.packages` block with:
```nix
home.packages = with pkgs; [
  ########################################
  # Dev tools (moved from systemPackages)
  ########################################
  git neovim wget rsync
  jq ripgrep fd bat
  gitleaks age sops unzip
  pythonEnv claude-code

  ########################################
  # Wayland / compositor
  ########################################
  grim slurp wl-clipboard swappy swww
  hyprcursor hyprpicker hyprpolkitagent
  fuzzel

  ########################################
  # Media
  ########################################
  vlc cava playerctl libnotify
  zoom deluge kdePackages.kdenlive

  ########################################
  # Apps
  ########################################
  brave thunderbird libreoffice
  nemo kdePackages.kate krita uniremote ghostty

  ########################################
  # Desktop tools (moved from desktop.nix systemPackages)
  ########################################
  wl-screenrec ydotool

  ########################################
  # CLI
  ########################################
  sshfs yt-dlp aria2 imagemagick
  delta lazygit tealdeer nix-your-shell comma helix

  ########################################
  # Audio / system UI
  ########################################
  pavucontrol nvd

  ########################################
  # Games
  ########################################
  supertux supertuxkart
];
```

Removed from home.packages vs current:
- `pamixer` — now using wpctl (Task 1)
- `pulseaudio` — violates wpctl-only rule
- `hyprpaper` — unused (exec.conf uses swww)
- `wev` — debug tool, use nix shell
- `socat` — not referenced, use nix shell
- `dart-sass` — no SCSS pipeline
- `bluez` — not a user package, it's a system service library

Also removed `programs.wofi.enable` from the programs block.

**Step 3: Remove `programs.wofi.enable = true;` from the programs block**

In the `programs = { ... }` block, delete the line:
```nix
wofi.enable      = true;
```

**Step 4: Commit**
```bash
git add profiles/home/base.nix
git commit -m "home: reorganize home.packages — move dev tools from system, remove dead weight"
```

---

## Task 6: Clean up family/default.nix

**Files:**
- Modify: `home/family/default.nix`

**Step 1: Remove `adw-gtk3` from `home.packages`**

In `home/family/default.nix`, the packages list is:
```nix
home.packages = with pkgs; [
  brave adw-gtk3
  ...
```

`adw-gtk3` is already pulled in via `gtk.theme.package = pkgs.adw-gtk3`. The explicit entry is redundant.

Change to:
```nix
home.packages = with pkgs; [
  brave
  vlc playerctl libnotify pavucontrol
  libreoffice
  steam supertux supertuxkart
  nemo wl-clipboard
  gnome-tweaks
];
```

**Step 2: Commit**
```bash
git add home/family/default.nix
git commit -m "home/family: remove redundant adw-gtk3 from packages"
```

---

## Task 7: Build and verify

**Step 1: Check for Nix evaluation errors first (faster than full build)**
```bash
nix flake check 2>&1 | head -40
```
Expected: no errors (warnings about substituters are OK)

**Step 2: Rebuild the current host**
```bash
nrs . 2>&1 | tail -30
```
Expected: successful switch with no errors

**Step 3: Verify gpg-agent starts**
```bash
systemctl --user status gpg-agent.service
gpg --list-keys
```

**Step 4: Verify wpctl works for audio (niri session)**

After switching to niri session, test volume keys. Or test manually:
```bash
wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
wpctl get-volume @DEFAULT_AUDIO_SINK@
```

**Step 5: Verify removed packages are gone**
```bash
which pamixer 2>&1  # should: not found
which pulseaudio 2>&1  # should: not found
which wf-recorder 2>&1  # should: not found
```

**Step 6: Final commit if any last-minute fixes were needed**

---

## Notes

- `swayosd` and `ydotool` were left in `desktop.nix` systemPackages because they may require udev rules or device permissions that work better at system level. Audit separately if needed.
- `wl-screenrec` was moved to `home.packages` via Task 5 (the base profile gets it) — if it should only be on desktop, move it to a `profiles/home/desktop.nix` instead.
- `foliate` and `koreader` in `profiles/home/surface.nix` left as-is — both are valid ebook readers for a tablet.
- The `programs.fuzzel` module conversion (to manage fuzzel config declaratively) is a follow-up improvement, not part of this cleanup.
