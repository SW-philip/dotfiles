# Secrets & Packages Consolidation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move shared secrets to `secrets/shared.yaml`, consolidate user packages from system profiles into home profiles, and fix a misplaced dconf block in `profiles/home/surface.nix`.

**Architecture:** Two independent tracks — secrets restructure (Nix side only; sops file operations are manual) and package consolidation (pure Nix moves). Track 1 updates `.sops.yaml` and the three host `config.nix` files to point shared secrets at `shared.yaml`. Track 2 moves seven packages from `profiles/desktop.nix` and one from `hosts/desktop/services.nix` into `profiles/home/desktop.nix`.

**Tech Stack:** sops-nix, NixOS modules, home-manager (NixOS-integrated — `nrs` only, never `home-manager switch`)

---

## Manual prerequisite (user must do before Task 3)

> These sops operations cannot be done by Claude — they require your age keys.

1. **Create `secrets/shared.yaml`** encrypted for all three keys (surface + desktop + family):
   ```
   sops --age $(cat ~/.config/sops/age/keys.txt | grep -o 'age1[^,]*') secrets/shared.yaml
   ```
   Add two keys:
   - `openweathermap_api_key` — copy value from `desktop.yaml` (same value is in `surface.yaml` and `family.yaml`)
   - `spotify_env` — copy value from `desktop.yaml` (same value is in `surface.yaml`)

2. **Strip from `secrets/desktop.yaml`**: remove `openweathermap_api_key` and `spotify_env`. Since the two remaining orphaned Spotify API keys have no Nix declaration, drop them too — that empties `desktop.yaml`. Delete the file.

3. **Strip from `secrets/surface.yaml`**: remove `openweathermap_api_key` and `spotify_env`. Keep `protonvpn_conf`, `msmtp_password`, `github_pat`.

4. **Delete `secrets/family.yaml`** — it will be empty after moving `openweathermap_api_key` to shared.

---

## Task 1: Update .sops.yaml — add shared.yaml creation rule

**Files:**
- Modify: `.sops.yaml`

**Step 1: Add the shared rule (all 3 keys)**

In `.sops.yaml`, add a new creation rule before the existing ones (most specific first is fine, but
shared catches a new path so order doesn't conflict):

```yaml
  - path_regex: secrets/shared\.yaml$
    key_groups:
      - age:
        - *surface
        - *desktop
        - *family
```

Result — `.sops.yaml` should look like:

```yaml
keys:
  - &surface age1REPLACE_WITH_SURFACE_AGE_KEY
  - &desktop age1REPLACE_WITH_DESKTOP_AGE_KEY
  - &family  age1pvgns0jcghzv2dx7yfc503aptsnv47chyge0s4x9a256pfvlwflsxqj5w2

creation_rules:
  - path_regex: secrets/shared\.yaml$
    key_groups:
      - age:
        - *surface
        - *desktop
        - *family
  - path_regex: secrets/surface\.yaml$
    key_groups:
      - age:
        - *surface
  - path_regex: secrets/desktop\.yaml$
    key_groups:
      - age:
        - *desktop
  - path_regex: secrets/family\.yaml$
    key_groups:
      - age:
        - *family
```

**Step 2: Commit**
```bash
git add .sops.yaml
git commit -m "sops: add shared.yaml creation rule (all 3 age keys)"
```

---

## Task 2: Update hosts/desktop/config.nix — point to shared.yaml

**Files:**
- Modify: `hosts/desktop/config.nix:44-55`

**Step 1: Change defaultSopsFile and remove machine-specific leftovers**

The orphaned keys are being dropped, so `desktop.yaml` will be deleted after the manual sops step.
Change `defaultSopsFile` to `shared.yaml` and keep the two secret declarations unchanged (they now
resolve from shared):

```nix
  sops = {
    defaultSopsFile = ../../secrets/shared.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.spotify_env = {
      owner = "prepko";
      path = "/run/secrets/spotify_env";
    };
    secrets.openweathermap_api_key = {
      owner = "prepko";
      path = "/run/secrets/openweathermap_api_key";
    };
  };
```

**Step 2: Commit**
```bash
git add hosts/desktop/config.nix
git commit -m "sops: desktop reads shared.yaml for spotify_env and openweathermap_api_key"
```

---

## Task 3: Update hosts/surface/config.nix — explicit sopsFile for shared secrets

**Files:**
- Modify: `hosts/surface/config.nix:35-41`

**Step 1: Override sopsFile for the two secrets that moved**

Surface keeps `defaultSopsFile = surface.yaml` (protonvpn_conf stays there). The two shared secrets
get an explicit `sopsFile` override:

```nix
  sops = {
    defaultSopsFile = ../../secrets/surface.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.protonvpn_conf = {};
    secrets.spotify_env = {
      sopsFile = ../../secrets/shared.yaml;
      owner = "prepko";
    };
    secrets.openweathermap_api_key = {
      sopsFile = ../../secrets/shared.yaml;
      owner = "prepko";
    };
  };
```

Note: `msmtp_password` and `github_pat` remain in `surface.yaml` and are declared in `msmtp.nix`
and wherever `github_pat` is used — no changes needed for those.

**Step 2: Commit**
```bash
git add hosts/surface/config.nix
git commit -m "sops: surface reads shared.yaml for spotify_env and openweathermap_api_key"
```

---

## Task 4: Update hosts/family/config.nix — point to shared.yaml

**Files:**
- Modify: `hosts/family/config.nix:15-22`

**Step 1: Change defaultSopsFile; keep the one secret declaration**

`family.yaml` will be empty (and deleted), so switch the default:

```nix
  sops = {
    defaultSopsFile = ../../secrets/shared.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.openweathermap_api_key = {
      owner = "family";
      path  = "/run/secrets/openweathermap_api_key";
    };
  };
```

**Step 2: Commit**
```bash
git add hosts/family/config.nix
git commit -m "sops: family reads shared.yaml for openweathermap_api_key"
```

---

## Task 5: Move packages from profiles/desktop.nix to profiles/home/desktop.nix

**Files:**
- Modify: `profiles/desktop.nix:55-68`
- Modify: `profiles/home/desktop.nix:20-25`

**Step 1: Remove user-facing packages from profiles/desktop.nix**

Delete the entire `environment.systemPackages` block (lines 55–68). These are all Wayland/GPU
user tools with no need for root or other users:

```nix
  # Delete this whole block:
  environment.systemPackages = with pkgs; [
    wayland-utils
    swayosd
    ydotool
    vulkan-tools
    mesa-demos
    drm_info
    smartmontools
  ];
```

**Step 2: Add them to profiles/home/desktop.nix**

Append to the existing `home.packages` list:

```nix
  home.packages = with pkgs; [
    awww
    wl-screenrec
    ncspot
    # Wayland / screen diagnostics
    wayland-utils
    swayosd
    ydotool
    vulkan-tools
    mesa-demos
    drm_info
    smartmontools
  ];
```

**Step 3: Commit**
```bash
git add profiles/desktop.nix profiles/home/desktop.nix
git commit -m "packages: move wayland/gpu tools from system to home/desktop"
```

---

## Task 6: Review hosts/desktop/services.nix packages — move dig, keep wireguard-tools

**Files:**
- Modify: `hosts/desktop/services.nix` (the `environment.systemPackages` block near top of Packages section)
- Modify: `profiles/home/desktop.nix`

**Step 1: Assessment**

Current `hosts/desktop/services.nix` has:
```nix
  environment.systemPackages = with pkgs; [
    dig
    wireguard-tools
  ];
```

- `wireguard-tools`: keep in system — `wg` and `wg-quick` need CAP_NET_ADMIN; root and systemd services use it
- `dig`: move to home — purely a user debugging tool

**Step 2: Remove dig from services.nix**

```nix
  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];
```

**Step 3: Add dig to profiles/home/desktop.nix**

Add `dig` to the `home.packages` list.

**Step 4: Commit**
```bash
git add hosts/desktop/services.nix profiles/home/desktop.nix
git commit -m "packages: move dig to home/desktop, keep wireguard-tools in system"
```

---

## Task 7: Fix misplaced dconf block in profiles/home/surface.nix

**Files:**
- Modify: `profiles/home/surface.nix:20-31`

**Step 1: Assessment**

The `org/gnome/desktop/background` block sets:
```
picture-uri = "file:///home/family/Pictures/KPDHWP.jpg"
```

This path is in the `family` user's home, on the family machine — not on surface. Surface runs Niri
(not GNOME), and the user is `prepko`. This block has no effect on surface and should be removed.

The `org/gnome/desktop/interface` block (color-scheme, cursor-theme, gtk-theme) is valid — it affects
GTK app theming even without a full GNOME session. Keep it.

**Step 2: Remove the background block**

Before:
```nix
  dconf.settings = {
    "org/gnome/desktop/interface" = lib.mkForce {
      color-scheme = "prefer-dark";
      cursor-theme = "BreezeX-RosePine-Linux";
      gtk-theme = "Adwaita-dark";
    };
    "org/gnome/desktop/background" = {
      picture-uri = "file:///home/family/Pictures/KPDHWP.jpg";
      picture-uri-dark = "file:///home/family/Pictures/KPDHWP.jpg";
      picture-options = "zoom";
    };
  };
```

After:
```nix
  dconf.settings = {
    "org/gnome/desktop/interface" = lib.mkForce {
      color-scheme = "prefer-dark";
      cursor-theme = "BreezeX-RosePine-Linux";
      gtk-theme = "Adwaita-dark";
    };
  };
```

**Step 3: Commit**
```bash
git add profiles/home/surface.nix
git commit -m "surface: remove family wallpaper path from dconf (wrong host)"
```

---

## Final verification

After the manual sops steps and `nrs` on each machine:

- Desktop: `cat /run/secrets/spotify_env` and `cat /run/secrets/openweathermap_api_key` should return values
- Surface: same + `cat /run/secrets/protonvpn_conf` should still work
- Family: `cat /run/secrets/openweathermap_api_key` as `family` user should work
- Desktop: `wayland-utils`, `swayosd`, etc. available in `prepko`'s PATH; not in root's PATH
