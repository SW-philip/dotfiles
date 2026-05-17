#!/usr/bin/env bash
# Reinstall lanzaboote for the Surface's existing system profile.
# Use this when you just need the bootloader working — no rebuild required.
set -euo pipefail

LUKS_UUID="YOUR-SURFACE-LUKS-UUID"
LUKS_NAME="cryptroot"
EFI_UUID="YOUR-SURFACE-EFI-UUID"
MOUNT="/mnt/surface"

cleanup() {
    echo "==> Cleaning up..."
    for d in run dev/pts dev sys proc; do
        sudo umount "$MOUNT/$d" 2>/dev/null || true
    done
    sudo umount -R "$MOUNT" 2>/dev/null || true
    sync
    sudo cryptsetup close "$LUKS_NAME" 2>/dev/null \
        || sudo dmsetup remove --force "$LUKS_NAME" 2>/dev/null \
        || true
}
trap cleanup EXIT

echo "==> Opening LUKS..."
sudo cryptsetup open "/dev/disk/by-uuid/$LUKS_UUID" "$LUKS_NAME"

echo "==> Mounting filesystems..."
sudo mkdir -p "$MOUNT"
sudo mount -o subvol=@,compress=zstd,noatime /dev/mapper/"$LUKS_NAME" "$MOUNT"
sudo mkdir -p "$MOUNT"/{home,boot}
sudo mount -o subvol=@home,compress=zstd,noatime /dev/mapper/"$LUKS_NAME" "$MOUNT/home"
sudo mount "/dev/disk/by-uuid/$EFI_UUID" "$MOUNT/boot"

echo "==> Setting up chroot..."
for d in proc sys dev dev/pts run; do sudo mount --bind /$d "$MOUNT/$d"; done

echo "==> Installing bootloader..."
sudo chroot "$MOUNT" /nix/var/nix/profiles/system/bin/switch-to-configuration boot

echo "==> Done! Safe to remove the Surface drive."
