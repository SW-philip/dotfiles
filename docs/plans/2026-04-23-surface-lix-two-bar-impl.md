# Surface Lix Migration + Two-Bar Waybar Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate the surface host to Lix and split its single-bar Waybar into a top bar (workspaces/media) and a bottom bar (health/time/toggles) with collapsing drawer groups.

**Architecture:** Two independent changes committed separately. Lix is a flake input added only to the surface nixosConfiguration. The Waybar split replaces the single `mainBar` attrset in the `else` branch of `home/waybar/default.nix` with two named bars.

**Tech Stack:** Nix flakes, NixOS modules, Lix, Waybar (home-manager `programs.waybar.settings`)

---

### Task 1: Add Lix to flake.nix

**Files:**
- Modify: `flake.nix`

**Step 1: Add lix-module input**

In `flake.nix`, inside the `inputs` attrset (after `lanzaboote`), add:

```nix
lix-module = {
  url = "https://git.lix.systems/lix-project/lix-module/archive/main.tar.gz";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**Step 2: Expose lix-module in outputs args**

Change the outputs function signature from:
```nix
outputs = inputs@{
  self,
  nixpkgs,
  nixpkgs-unstable,
  nixos-hardware,
  hyprland,
  home-manager,
  home-manager-unstable,
  lanzaboote,
  claude-code,
  ...
}:
```
To (add `lix-module` before `...`):
```nix
outputs = inputs@{
  self,
  nixpkgs,
  nixpkgs-unstable,
  nixos-hardware,
  hyprland,
  home-manager,
  home-manager-unstable,
  lanzaboote,
  claude-code,
  lix-module,
  ...
}:
```

**Step 3: Add lix-module to surface modules list**

In the `surface` nixosConfiguration modules list, add after `lanzaboote.nixosModules.lanzaboote`:
```nix
lix-module.nixosModules.default
```

**Step 4: Verify flake evaluates**

```bash
cd ~/nixos && nix flake show 2>&1 | head -30
```
Expected: no eval errors, surface host still listed.

**Step 5: Commit**

```bash
git add flake.nix
git commit -m "feat: add Lix to surface nixosConfiguration"
```

---

### Task 2: Replace surface single bar with two-bar layout

**Files:**
- Modify: `home/waybar/default.nix` (the `else` branch, lines ~152–204)

**Context:** The surface bar lives in the `else` branch of the `if isDesktop then { ... } else { ... }` expression in `programs.waybar.settings`. Replace the entire `mainBar` attrset with two bars: `surfaceTopBar` and `surfaceBottomBar`.

**Step 1: Replace the surface else branch**

Find this block (starting around line 152):
```nix
} else {
  # ── Surface: single bar — media left, clock center, controls right ────
  mainBar = {
    name = "main-bar";
    ...
  };
};
```

Replace the entire `else` branch content with:

```nix
} else {
  # ── Surface top: workspaces + theme swap left, media right ────────────
  surfaceTopBar = {
    name = "surface-top";
    layer = "top";
    position = "top";
    exclusive = false;
    output = "eDP-1";
    height = 45;
    modules-left   = [ "hyprland/workspaces" "custom/choose_mode" ];
    modules-center = [];
    modules-right  = [ "custom/volume" "custom/sqlch" "custom/mpris" ];
    "custom/choose_mode" = {
      exec = "${chooseModeExec}";
      on-click = "toggle-theme";
      return-type = "json";
      interval = "once";
    };
  };
  # ── Surface bottom: health left, time center, system right ────────────
  surfaceBottomBar = {
    name = "surface-bottom";
    layer = "top";
    position = "bottom";
    exclusive = false;
    output = "eDP-1";
    height = 45;
    modules-left   = [ "custom/cpu_temp" "custom/battery" "custom/btrfs" "custom/sleep_drain" ];
    modules-center = [ "custom/clock" "custom/weather" ];
    modules-right  = [
      "group/connectivity"
      "tray"
      "custom/flake_drift"
      "group/toggles"
      "group/actions"
    ];
    "group/connectivity" = {
      orientation = "horizontal";
      modules = [ "custom/bluetooth" "custom/network" ];
    };
    "group/toggles" = {
      orientation = "horizontal";
      drawer = {
        transition-duration = 500;
        transition-left-to-right = false;
      };
      modules = [
        "custom/power_profile"
        "custom/idle_inhibit"
        "custom/dnd"
      ];
    };
    "group/actions" = {
      orientation = "horizontal";
      drawer = {
        transition-duration = 500;
        transition-left-to-right = false;
      };
      modules = [
        "custom/wleave"
        "custom/uniremote"
      ];
    };
  };
};
```

**Step 2: Verify flake evaluates**

```bash
cd ~/nixos && nix flake show 2>&1 | head -30
```
Expected: no eval errors.

**Step 3: Build surface config without switching**

```bash
nix build .#nixosConfigurations.surface.config.system.build.toplevel 2>&1 | tail -20
```
Expected: build succeeds (or only network-fetch output).

**Step 4: Commit**

```bash
git add home/waybar/default.nix
git commit -m "feat(surface): split single waybar into top + bottom bars with drawer groups"
```

---

### Task 3: Rebuild and test on the surface

**Step 1: Rebuild**

```bash
nrs
```

**Step 2: Verify both bars appear**

After rebuild and re-login (or `systemctl --user restart waybar`), confirm:
- Top bar shows workspaces + theme toggle on left; volume/sqlch/mpris on right
- Bottom bar shows health metrics left, clock/weather center, system controls right
- Hovering over the toggles group expands power_profile, idle_inhibit, dnd
- Hovering over the actions group expands uniremote from behind wleave

**Step 3: If bars don't appear**

Check: `systemctl --user status waybar` and `journalctl --user -u waybar -n 50`

Common cause: Waybar doesn't know about `hyprland/workspaces` module if the Hyprland socket isn't available. If that module errors, replace with `wlr/taskbar` or remove it.
