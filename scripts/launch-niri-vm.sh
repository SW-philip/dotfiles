#!/usr/bin/env bash
# launch-niri-vm.sh — Start the Niri/Wayland KVM guest manually
#
# Usage:
#   ./scripts/launch-niri-vm.sh [/path/to/disk.qcow2] [--iso /path/to/file.iso]
#
# Defaults:
#   DISK  = ~/niri-vm.qcow2 (or first positional arg)
#   MEM   = 4096 (MB)   — override: MEM=8192 ./launch-niri-vm.sh
#   CPUS  = 4           — override: CPUS=2 ./launch-niri-vm.sh
#
# Create a fresh disk:
#   qemu-img create -f qcow2 ~/niri-vm.qcow2 20G
#
# SSH into the guest (password: nixos):
#   ssh -p 2222 prepko@localhost

set -euo pipefail

DISK="${HOME}/niri-vm.qcow2"
ISO=""
MEM="${MEM:-4096}"
CPUS="${CPUS:-4}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iso) ISO="$2"; shift 2 ;;
    *)     DISK="$1"; shift ;;
  esac
done

if [[ ! -f "$DISK" ]]; then
  echo "ERROR: disk image not found: $DISK"
  echo "Create with: qemu-img create -f qcow2 \"$DISK\" 20G"
  exit 1
fi

ISO_ARGS=()
BOOT_ORDER="c"
if [[ -n "$ISO" ]]; then
  [[ ! -f "$ISO" ]] && { echo "ERROR: ISO not found: $ISO"; exit 1; }
  ISO_ARGS=(-drive "file=${ISO},media=cdrom,readonly=on,if=ide" )
  BOOT_ORDER="dc"   # CD first so the installer runs; disk takes over after install
fi

exec qemu-system-x86_64 \
  -name "niri-vm,debug-threads=on" \
  -machine q35,accel=kvm \
  -cpu host \
  -smp "cores=${CPUS},threads=2" \
  -m "${MEM}M" \
  \
  -drive "file=${DISK},if=virtio,cache=writeback,discard=unmap,format=qcow2" \
  "${ISO_ARGS[@]+"${ISO_ARGS[@]}"}" \
  \
  -device virtio-gpu-gl,xres=1920,yres=1080 \
  -display spice-app,gl=on \
  \
  -device virtio-serial \
  -chardev spicevmc,id=vdagent,debug=0,name=vdagent \
  -device virtserialport,chardev=vdagent,name=com.redhat.spice.0 \
  \
  -audiodev spice,id=audio0 \
  -device virtio-sound-pci,audiodev=audio0 \
  \
  -device virtio-net-pci,netdev=net0 \
  -netdev "user,id=net0,hostfwd=tcp::2222-:22" \
  \
  -device virtio-balloon \
  -device virtio-rng-pci \
  -device qemu-xhci \
  -device virtio-tablet \
  \
  -rtc base=localtime,clock=host \
  -boot "order=${BOOT_ORDER},menu=off" \
  "$@"
