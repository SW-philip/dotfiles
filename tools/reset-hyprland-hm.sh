#!/usr/bin/env bash
set -euo pipefail

echo "== Hyprland + Home Manager hard reset =="
echo

### 0. Sanity checks ###########################################################

if [[ -z "${USER:-}" ]]; then
  echo "ERROR: USER not set"
  exit 1
fi

if [[ ! -d "$PWD/.git" ]]; then
  echo "WARNING: not running from a git repo"
fi

### 1. Stop user session + kill stray Hyprland #################################

echo "-- Stopping user graphical session targets"
systemctl --user stop hyprland-session.target 2>/dev/null || true
systemctl --user stop graphical-session.target 2>/dev/null || true

echo "-- Killing stray Hyprland processes"
pkill -f Hyprland || true
sleep 1

### 2. Remove poisoned symlinks #################################################

HYPR_DIR="$HOME/.config/hypr"
HYPR_CONF="$HYPR_DIR/hyprland.conf"

if [[ -L "$HYPR_CONF" || -f "$HYPR_CONF" ]]; then
  echo "-- Removing $HYPR_CONF"
  rm -f "$HYPR_CONF"
else
  echo "-- No existing hyprland.conf to remove"
fi

### 3. Show lingering hm-generated configs (forensics only) ####################

echo
echo "-- Existing hm_hyprhyprland.conf artifacts in /nix/store:"
ls -1 /nix/store/*hm_hyprhyprland.conf 2>/dev/null || echo "  (none)"

### 4. Rebuild system + Home Manager ###########################################

echo
echo "-- Rebuilding system from flake"
sudo nixos-rebuild switch --flake .#surface

echo
echo "-- Re-running Home Manager activation (verbose)"
home-manager switch --impure --verbose

### 5. Verify resulting config #################################################

echo
echo "-- Verifying final hyprland.conf"

if [[ ! -e "$HYPR_CONF" ]]; then
  echo "ERROR: hyprland.conf was not recreated"
  exit 1
fi

FINAL_CONF="$(readlink -f "$HYPR_CONF")"
echo "  -> $FINAL_CONF"

echo
echo "-- Checking for forbidden plugin directives"

if rg -q "hyprctl plugin|plugin \{" "$FINAL_CONF"; then
  echo "ERROR: plugin directives still present!"
  echo
  rg "hyprctl plugin|plugin \{" "$FINAL_CONF"
  exit 1
else
  echo "OK: no plugin directives found"
fi

### 6. Final instructions #############################
