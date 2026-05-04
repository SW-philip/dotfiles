# Niri + Ironbar Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add niri as a selectable Wayland session alongside Hyprland, with ironbar as its bar, using systemd session targets to prevent any bar from starting in the wrong compositor.

**Architecture:** `programs.niri.enable = true` registers the niri session desktop file system-wide (both hosts). Waybar is bound to `hyprland-session.target` and ironbar to `niri-session.target` — each bar only starts inside its own compositor. Both sessions appear in tuigreet/GDM with no flake changes needed.

**Tech Stack:** NixOS 25.11, home-manager 25.11, niri (nixpkgs), ironbar (nixpkgs), KDL config format for niri, TOML for ironbar

---

### Task 1: Create `profiles/niri.nix` (system-level)

**Files:**
- Create: `profiles/niri.nix`

**Step 1: Create the file**

```nix
# profiles/niri.nix
# Niri compositor (system-level) — mirrors profiles/hyprland.nix
{ pkgs, ... }:
{
  ############################################################
  # Niri compositor (system-level)
  ############################################################
  programs.niri = {
    enable = true;
    package = pkgs.niri;
  };

  ############################################################
  # XDG portal — gnome portal handles niri sessions
  ############################################################
  # programs.niri.enable already adds xdg-desktop-portal-gnome
  # for niri sessions. We just ensure gtk portal is also present
  # for fallback (already pulled in by hyprland profile on shared hosts).

  ############################################################
  # Wayland session environment (shared with hyprland profile)
  ############################################################
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    GDK_BACKEND    = "wayland,x11";
    GTK_USE_PORTAL = "1";
  };
}
```

**Step 2: Verify it builds (dry run)**

```bash
cd /home/prepko/nixos
sudo nixos-rebuild dry-build --flake .#desktop 2>&1 | tail -20
```

Expected: build succeeds (no errors). Ignore warnings about unused inputs.

**Step 3: Commit**

```bash
git add profiles/niri.nix
git -c commit.gpgsign=false commit -m "feat: add system-level niri profile"
```

---

### Task 2: Import niri profile into both hosts

**Files:**
- Modify: `hosts/desktop/config.nix`
- Modify: `hosts/surface/config.nix`

**Step 1: Add import to desktop config**

In `hosts/desktop/config.nix`, add `../../profiles/niri.nix` to the imports list, right after `../../profiles/hyprland.nix`. The imports block currently looks like:

```nix
imports = [
  ../../profiles/base.nix
  ../../profiles/desktop.nix
  ../../profiles/hyprland.nix
  ...
```

Add the line so it reads:
```nix
  ../../profiles/hyprland.nix
  ../../profiles/niri.nix
```

**Step 2: Add import to surface config**

Same edit in `hosts/surface/config.nix` — add `../../profiles/niri.nix` after `../../profiles/hyprland.nix`.

**Step 3: Verify both hosts build**

```bash
sudo nixos-rebuild dry-build --flake .#desktop 2>&1 | tail -5
sudo nixos-rebuild dry-build --flake .#surface 2>&1 | tail -5
```

Expected: both succeed.

**Step 4: Commit**

```bash
git add hosts/desktop/config.nix hosts/surface/config.nix
git -c commit.gpgsign=false commit -m "feat: import niri profile into desktop and surface hosts"
```

---

### Task 3: Bind waybar to `hyprland-session.target`

**Files:**
- Modify: `home/waybar/default.nix`

**Step 1: Add `target` to the waybar systemd block**

In `home/waybar/default.nix`, find the `programs.waybar` block. It currently has:

```nix
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    style = import ./style.nix p;
```

Change it to:

```nix
  programs.waybar = {
    enable = true;
    systemd = {
      enable = true;
      target = "hyprland-session.target";
    };
    style = import ./style.nix p;
```

This prevents waybar from auto-starting when you log into a niri session (niri only activates `niri-session.target`, not `hyprland-session.target`).

**Step 2: Verify build**

```bash
sudo nixos-rebuild dry-build --flake .#desktop 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add home/waybar/default.nix
git -c commit.gpgsign=false commit -m "fix: bind waybar to hyprland-session.target to prevent niri session bleed"
```

---

### Task 4: Create `home/niri/default.nix`

**Files:**
- Create: `home/niri/default.nix`

This module wires together the niri config file, ironbar config, and the ironbar systemd service.

**Step 1: Create the file**

```nix
# home/niri/default.nix
# Niri home-manager config — cleanroom compositor for focused work
{ config, pkgs, lib, ... }:
let
  isDesktop = config.myConfig.isDesktop;
in
{
  ########################################
  # Niri compositor config
  ########################################
  xdg.configFile."niri/config.kdl".source = ./config.kdl;

  ########################################
  # Ironbar status bar
  ########################################
  home.packages = [ pkgs.ironbar ];

  xdg.configFile."ironbar/config.toml".source = ./ironbar.toml;

  systemd.user.services.ironbar = {
    Unit = {
      Description = "Ironbar status bar";
      Documentation = "https://github.com/JakeStanger/ironbar";
      After    = [ "niri-session.target" ];
      PartOf   = [ "niri-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.ironbar}/bin/ironbar";
      Restart   = "on-failure";
    };
    Install.WantedBy = [ "niri-session.target" ];
  };
}
```

**Step 2: Verify build (file is not imported yet — this just checks syntax)**

```bash
nix-instantiate --parse home/niri/default.nix
```

Expected: prints the parsed expression without errors.

---

### Task 5: Create niri config file `home/niri/config.kdl`

**Files:**
- Create: `home/niri/config.kdl`

Niri uses KDL (not TOML/INI). This is the "cleanroom" config — minimal gaps, soft focus ring, clean borders.

**Step 1: Create the file**

```kdl
// home/niri/config.kdl — niri cleanroom compositor config

// ── Input ──────────────────────────────────────────────────
input {
    keyboard {
        xkb {
            layout "us"
        }
        repeat-delay 250
        repeat-rate 40
    }

    touchpad {
        tap
        natural-scroll
        scroll-factor 0.6
    }

    mouse {
        accel-speed 0.0
    }

    focus-follows-mouse max-scroll-amount="0%"
}

// ── Outputs ────────────────────────────────────────────────
// Desktop: dual 1080p
output "DP-2" {
    mode "1920x1080@60.000"
    position x=0 y=0
    scale 1.0
}
output "DP-3" {
    mode "1920x1080@60.000"
    position x=1920 y=0
    scale 1.0
}
// Surface: HiDPI internal display
output "eDP-1" {
    mode "2160x1440@60.000"
    scale 1.5
}

// ── Layout ────────────────────────────────────────────────
layout {
    gaps 12

    border {
        width 2
        active-color "#c4a7e7"    // rose-pine: iris
        inactive-color "#393552"  // rose-pine: highlight low
        urgent-color "#eb6f92"    // rose-pine: love
    }

    focus-ring {
        off
    }

    preset-column-widths {
        proportion 0.333
        proportion 0.5
        proportion 0.666
        proportion 1.0
    }

    default-column-width { proportion 0.5; }

    struts {
        top 4
    }
}

// ── Appearance ────────────────────────────────────────────
prefer-no-csd

cursor {
    xcursor-theme "ComixCursors-Blue"
    xcursor-size 24
}

// ── Animations ────────────────────────────────────────────
animations {
    slowdown 0.8

    workspace-switch {
        spring damping-ratio=1.0 stiffness=800 epsilon=0.0001
    }
    window-open {
        duration-ms 150
        easing "ease-out-expo"
    }
    window-close {
        duration-ms 100
        easing "ease-out-quad"
    }
}

// ── Window rules ──────────────────────────────────────────
window-rule {
    match is-floating=true
    shadow {
        on
        softness 30
        offset x=0 y=4
        color "#0d0c0f80"
    }
}

// ── Bindings ──────────────────────────────────────────────
binds {
    // Apps
    Mod+Return { spawn "ghostty"; }
    Mod+Space  { spawn "fuzzel"; }
    Mod+E      { spawn "nemo"; }

    // Windows
    Mod+Q { close-window; }
    Mod+F { fullscreen-window; }
    Mod+Shift+F { toggle-window-floating; }

    // Focus — hjkl or arrows
    Mod+H { focus-column-left; }
    Mod+L { focus-column-right; }
    Mod+J { focus-window-down; }
    Mod+K { focus-window-up; }
    Mod+Left  { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Down  { focus-window-down; }
    Mod+Up    { focus-window-up; }

    // Move windows
    Mod+Shift+H { move-column-left; }
    Mod+Shift+L { move-column-right; }
    Mod+Shift+J { move-window-down; }
    Mod+Shift+K { move-window-up; }

    // Resize
    Mod+R { switch-preset-column-width; }
    Mod+Shift+R { reset-window-height; }
    Mod+Minus { set-column-width "-5%"; }
    Mod+Equal { set-column-width "+5%"; }
    Mod+Shift+Minus { set-window-height "-5%"; }
    Mod+Shift+Equal { set-window-height "+5%"; }

    // Workspaces
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+Shift+1 { move-column-to-workspace 1; }
    Mod+Shift+2 { move-column-to-workspace 2; }
    Mod+Shift+3 { move-column-to-workspace 3; }
    Mod+Shift+4 { move-column-to-workspace 4; }
    Mod+Shift+5 { move-column-to-workspace 5; }
    Mod+Tab        { focus-workspace-down; }
    Mod+Shift+Tab  { focus-workspace-up; }

    // Monitors
    Mod+Comma  { focus-monitor-left; }
    Mod+Period { focus-monitor-right; }
    Mod+Shift+Comma  { move-column-to-monitor-left; }
    Mod+Shift+Period { move-column-to-monitor-right; }

    // Scroll through columns
    Mod+WheelScrollRight cooldown-ms=150 { focus-column-right; }
    Mod+WheelScrollLeft  cooldown-ms=150 { focus-column-left; }

    // Media / system
    XF86AudioRaiseVolume  allow-when-locked=true { spawn "pamixer" "--increase" "5"; }
    XF86AudioLowerVolume  allow-when-locked=true { spawn "pamixer" "--decrease" "5"; }
    XF86AudioMute         allow-when-locked=true { spawn "pamixer" "--toggle-mute"; }
    XF86AudioPlay  { spawn "playerctl" "play-pause"; }
    XF86AudioNext  { spawn "playerctl" "next"; }
    XF86AudioPrev  { spawn "playerctl" "previous"; }
    XF86MonBrightnessUp   { spawn "brightnessctl" "set" "+5%"; }
    XF86MonBrightnessDown { spawn "brightnessctl" "set" "5%-"; }

    // Screenshot
    Print { screenshot; }
    Ctrl+Print { screenshot-screen; }
    Alt+Print  { screenshot-window; }

    // Session
    Mod+Shift+E { quit; }
    Mod+Shift+P { power-off-monitors; }
}
```

**Step 2: No build step needed** — this is a plain config file, not Nix.

---

### Task 6: Create ironbar config `home/niri/ironbar.toml`

**Files:**
- Create: `home/niri/ironbar.toml`

Ironbar uses TOML. Keep it minimal — this is the cleanroom bar.

**Step 1: Create the file**

```toml
# home/niri/ironbar.toml — minimal bar for the niri cleanroom session

position = "top"
anchor_to_edges = true
height = 36

[[start]]
type = "niri_workspaces"
name = "workspaces"

[start.name_map]
"1" = "1"
"2" = "2"
"3" = "3"
"4" = "4"
"5" = "5"

[[center]]
type = "clock"
name = "clock"
format = "%a %d %b  %H:%M"

[[end]]
type = "tray"
name = "tray"
```

---

### Task 7: Import `home/niri` into `profiles/home/base.nix`

**Files:**
- Modify: `profiles/home/base.nix`

**Step 1: Add the import**

In `profiles/home/base.nix`, the imports block currently reads:

```nix
  imports = [
    ../../modules/home-options.nix
    ../../home/waybar
    ../../home/mako
    ../../cachix.nix
  ];
```

Add niri after waybar:

```nix
  imports = [
    ../../modules/home-options.nix
    ../../home/waybar
    ../../home/mako
    ../../home/niri
    ../../cachix.nix
  ];
```

**Step 2: Verify full build**

```bash
sudo nixos-rebuild dry-build --flake .#desktop 2>&1 | tail -10
```

Expected: succeeds. If ironbar is not found in nixpkgs, you'll get an error like `attribute 'ironbar' missing` — see note below.

> **Note:** If `pkgs.ironbar` is not available in nixos-25.11, add it via `nixpkgs-unstable`:
> In `home/niri/default.nix` change `pkgs.ironbar` to `pkgsUnstable.ironbar` — but first check `nix search nixpkgs ironbar` to confirm availability.

**Step 3: Commit everything**

```bash
git add home/niri/
git -c commit.gpgsign=false commit -m "feat: add niri home module with ironbar service tied to niri-session.target"
git add profiles/home/base.nix
git -c commit.gpgsign=false commit -m "feat: import niri home module into base profile"
```

---

### Task 8: Live test on desktop

**Step 1: Switch to the new config**

```bash
sudo nixos-rebuild switch --flake .#desktop
```

**Step 2: Verify niri appears in tuigreet**

Log out. At the tuigreet screen, press `F2` (or the session key) — you should see both `hyprland` and `niri` as selectable sessions.

**Step 3: Log into niri, verify ironbar starts**

After logging in with niri:
```bash
systemctl --user status ironbar
```
Expected: `active (running)`

**Step 4: Log into hyprland, verify waybar starts and ironbar does NOT**

```bash
systemctl --user status waybar    # should be active
systemctl --user status ironbar   # should be inactive/dead
```

**Step 5: Commit any config tweaks made during live testing**

---

### Task 9: Adjust niri/ironbar styling (optional polish)

If the bar or compositor config needs visual tweaks after live testing:

- Ironbar CSS: create `home/niri/ironbar.css` and reference it in `ironbar.toml` with `css_path = "~/.config/ironbar/ironbar.css"`
- Rose-Pine colors reference: `#232136` base, `#e0def4` text, `#c4a7e7` iris, `#eb6f92` love, `#f6c177` gold, `#9ccfd8` foam
- Niri border/gaps: edit `home/niri/config.kdl` layout block

Commit any styling changes before considering the feature complete.
