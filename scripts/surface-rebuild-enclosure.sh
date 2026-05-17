#!/usr/bin/env bash
# Rebuild the Surface NixOS config while its NVMe is in a USB enclosure.
# Run from the desktop as your normal user (sudo will be prompted as needed).
set -euo pipefail

LUKS_UUID="YOUR-SURFACE-LUKS-UUID"
LUKS_NAME="cryptroot"
EFI_UUID="YOUR-SURFACE-EFI-UUID"
MOUNT="/mnt/surface"
FLAKE_DIR="$HOME/nixos"
FLAKE_ATTR="surface"

cleanup() {
    echo "==> Cleaning up..."
    sudo umount -R "$MOUNT" 2>/dev/null || true
    sync
    sudo cryptsetup close "$LUKS_NAME" 2>/dev/null \
        || sudo dmsetup remove --force "$LUKS_NAME" 2>/dev/null \
        || true
}
trap cleanup EXIT

# ── Mount ─────────────────────────────────────────────────────
echo "==> Opening LUKS (you may be prompted for the Surface passphrase)..."
sudo cryptsetup open "/dev/disk/by-uuid/$LUKS_UUID" "$LUKS_NAME"

echo "==> Mounting filesystems..."
sudo mkdir -p "$MOUNT"
sudo mount -o subvol=@,compress=zstd,noatime /dev/mapper/"$LUKS_NAME" "$MOUNT"
sudo mkdir -p "$MOUNT"/{home,boot}
sudo mount -o subvol=@home,compress=zstd,noatime /dev/mapper/"$LUKS_NAME" "$MOUNT/home"
sudo mount "/dev/disk/by-uuid/$EFI_UUID" "$MOUNT/boot"

# ── Build ─────────────────────────────────────────────────────
echo "==> Building surface config..."
cd "$FLAKE_DIR"
nixos-rebuild build --flake ".#$FLAKE_ATTR"
RESULT=$(readlink -f result)
echo "    Result: $RESULT"

# ── Deploy ────────────────────────────────────────────────────
echo "==> Copying closure into Surface's /nix/store..."
nix copy --to "local?root=$MOUNT" "$RESULT"

echo "==> Setting system profile..."
sudo nix-env -p "$MOUNT/nix/var/nix/profiles/system" --set "$RESULT"

echo "==> Installing bootloader..."
sudo nixos-enter --root "$MOUNT" -- "$RESULT/bin/switch-to-configuration" boot

# ── Cleanup handled by trap ───────────────────────────────────
echo "==> Done! Safe to remove the Surface drive."
