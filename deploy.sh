#!/usr/bin/env bash
set -e

read -rp "Commit message: " msg
[[ -z "$msg" ]] && { echo "Commit message required."; exit 1; }

cd /home/prepko/nixos

git add .
git commit -m "$msg"
git push -u origin main

sudo rm -f /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI
sudo nixos-rebuild switch --flake /home/prepko/nixos#desktop
