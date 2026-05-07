#!/usr/bin/env bash
# enroll-secureboot-tpm2.sh
# Enroll sbctl Secure Boot keys and/or TPM2 LUKS unlock for this machine.
#
# ORDERING MATTERS:
#   Step 1 — Enroll Secure Boot keys (requires UEFI in Setup Mode)
#   Step 2 — Reboot and verify Secure Boot is ON
#   Step 3 — Run this script again to enroll TPM2 (PCR 7 must reflect live SB state)
#
# Usage:
#   sudo ./enroll-secureboot-tpm2.sh          # interactive
#   sudo ./enroll-secureboot-tpm2.sh --sb      # Secure Boot enrollment only
#   sudo ./enroll-secureboot-tpm2.sh --tpm2    # TPM2 enrollment only
#   sudo ./enroll-secureboot-tpm2.sh --wipe-tpm2  # Remove TPM2 slots (after firmware update etc.)

set -euo pipefail

##############################################################
# Machine-specific LUKS device map
##############################################################
declare -A LUKS_DESCS

case "$(hostname)" in
  desktop)
    MACHINE="desktop"
    LUKS_DESCS=(
      ["YOUR-DESKTOP-ROOT-UUID"]="root+home (nvme)"
      ["YOUR-DESKTOP-SRV-UUID"]="backup+srv (3TB)"
    )
    ;;
  surface)
    MACHINE="surface"
    LUKS_DESCS=(
      ["YOUR-SURFACE-LUKS-UUID"]="cryptroot (nvme)"
    )
    ;;
  family)
    MACHINE="family"
    LUKS_DESCS=(
      ["YOUR-FAMILY-LUKS-UUID"]="cryptroot (ssd)"
    )
    ;;
  *)
    echo "ERROR: Unrecognised hostname '$(hostname)'. Edit this script to add your machine."
    exit 1
    ;;
esac

##############################################################
# Helpers
##############################################################
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}==> $*${NC}"; }
ok()    { echo -e "${GREEN}  ✓ $*${NC}"; }
warn()  { echo -e "${YELLOW}  ! $*${NC}"; }
err()   { echo -e "${RED}ERROR: $*${NC}" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)."
    exit 1
  fi
}

confirm() {
  local prompt="$1"
  read -rp "$(echo -e "${YELLOW}${prompt} [y/N]: ${NC}")" ans
  [[ "${ans,,}" == "y" ]]
}

##############################################################
# Secure Boot status
##############################################################
sb_status() {
  info "Secure Boot status"
  sbctl status
  echo
}

sb_enrolled() {
  # Returns 0 if keys are already enrolled
  sbctl status 2>/dev/null | grep -q "Secure Boot:.*enabled" || \
  sbctl status 2>/dev/null | grep -q "Keys:.*Enrolled"
}

in_setup_mode() {
  sbctl status 2>/dev/null | grep -qi "Setup Mode:.*Enabled\|setup mode.*on"
}

##############################################################
# Step 1: Enroll Secure Boot keys
##############################################################
do_secureboot() {
  info "=== STEP 1: Secure Boot key enrollment ==="
  sb_status

  if sbctl status 2>/dev/null | grep -q "Secure Boot:.*enabled"; then
    ok "Secure Boot is already active."
    if confirm "Re-enroll keys anyway? (usually not needed)"; then
      :
    else
      return 0
    fi
  fi

  if ! in_setup_mode; then
    warn "UEFI is NOT in Setup Mode."
    echo "  You must enter your UEFI firmware and clear/reset Secure Boot keys"
    echo "  (look for 'Reset to Setup Mode' or 'Clear Secure Boot Keys')."
    echo "  Then reboot and re-run this script."
    if ! confirm "Continue anyway? (only if you know your firmware auto-enables setup mode)"; then
      return 1
    fi
  fi

  # Create keys if missing
  if [[ ! -f /var/lib/sbctl/keys/db/db.pem ]]; then
    info "Creating sbctl key set..."
    sbctl create-keys
    ok "Keys created at /var/lib/sbctl/keys/"
  else
    ok "sbctl keys already exist — skipping create."
  fi

  # Enroll
  info "Enrolling keys into firmware..."
  warn "Including Microsoft keys (--microsoft) for firmware/option-ROM compatibility."
  warn "Omit --microsoft only if you're sure your hardware doesn't need them."
  if confirm "Include Microsoft keys (recommended for most hardware)?"; then
    sbctl enroll-keys --microsoft
  else
    sbctl enroll-keys
  fi

  ok "Secure Boot keys enrolled."
  echo
  echo -e "${YELLOW}NEXT STEPS:${NC}"
  echo "  1. Run: nrs   (nixos-rebuild switch — lanzaboote will sign the boot files)"
  echo "  2. Reboot."
  echo "  3. Verify Secure Boot is ON: sbctl status"
  echo "  4. Re-run this script with --tpm2 to enroll TPM2 unlock."
  echo
}

##############################################################
# Step 2: Enroll TPM2 into LUKS
##############################################################
do_tpm2() {
  info "=== STEP 2: TPM2 LUKS enrollment (machine: ${MACHINE}) ==="

  # Safety check — PCR 7 must reflect live SB state
  local sb_active
  sb_active=$(bootctl 2>/dev/null | grep "Secure Boot:" | awk '{print $3}' || echo "unknown")
  if [[ "$sb_active" != "enabled" ]]; then
    err "Secure Boot does not appear to be active (status: ${sb_active})."
    echo "  TPM2 enrollment with PCR 7 REQUIRES Secure Boot to be ON."
    echo "  Enrolling now would bind to an insecure PCR 7 value and will break"
    echo "  unlock after you enable Secure Boot."
    echo
    echo "  Complete Step 1 (--sb) and reboot first."
    if ! confirm "Override and enroll anyway? (NOT recommended)"; then
      return 1
    fi
  else
    ok "Secure Boot is active — safe to bind TPM2 to PCR 7."
  fi

  # Check TPM2 is accessible
  if ! tpm2_getcap properties-fixed &>/dev/null; then
    err "TPM2 not accessible. Check: dmesg | grep tpm"
    return 1
  fi
  ok "TPM2 device is accessible."
  echo

  for uuid in "${!LUKS_DESCS[@]}"; do
    local dev="/dev/disk/by-uuid/${uuid}"
    local desc="${LUKS_DESCS[$uuid]}"
    local mapper_name

    if [[ ! -e "$dev" ]]; then
      warn "Device not found (skipping): $dev ($desc)"
      continue
    fi

    mapper_name=$(cryptsetup status 2>/dev/null | grep "^/dev/mapper" | head -1 || true)
    info "LUKS device: $dev"
    echo "  Description : $desc"
    echo "  UUID        : $uuid"

    # Check if TPM2 slot already exists
    if systemd-cryptenroll --list-token "$dev" 2>/dev/null | grep -q "tpm2"; then
      ok "TPM2 slot already enrolled for this device."
      if ! confirm "Re-enroll? (wipes existing TPM2 slot first)"; then
        echo
        continue
      fi
      info "Wiping existing TPM2 slot..."
      systemd-cryptenroll --wipe-slot=tpm2 "$dev"
    fi

    echo
    warn "You will be prompted for your existing LUKS passphrase to authorise the new slot."
    if confirm "Enroll TPM2 (PCR 7) for $desc?"; then
      systemd-cryptenroll \
        --tpm2-device=auto \
        --tpm2-pcrs=7 \
        "$dev"
      ok "TPM2 enrolled for $dev"
    else
      warn "Skipped $dev"
    fi
    echo
  done

  echo -e "${GREEN}TPM2 enrollment complete.${NC}"
  echo "Test by rebooting — the disk(s) should unlock automatically."
  echo "Your passphrase still works as fallback."
  echo
  echo "If TPM2 unlock breaks after a firmware update:"
  echo "  sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-uuid/<UUID>"
  echo "  Then re-run this script with --tpm2."
  echo
}

##############################################################
# Wipe TPM2 slots
##############################################################
do_wipe_tpm2() {
  info "=== Wiping TPM2 LUKS slots (machine: ${MACHINE}) ==="
  warn "This removes TPM2 auto-unlock. Your passphrase will still work."
  echo

  for uuid in "${!LUKS_DESCS[@]}"; do
    local dev="/dev/disk/by-uuid/${uuid}"
    local desc="${LUKS_DESCS[$uuid]}"

    if [[ ! -e "$dev" ]]; then
      warn "Device not found (skipping): $dev ($desc)"
      continue
    fi

    if systemd-cryptenroll --list-token "$dev" 2>/dev/null | grep -q "tpm2"; then
      if confirm "Wipe TPM2 slot from $dev ($desc)?"; then
        systemd-cryptenroll --wipe-slot=tpm2 "$dev"
        ok "TPM2 slot wiped from $dev"
      fi
    else
      info "No TPM2 slot found on $dev ($desc) — nothing to wipe."
    fi
    echo
  done
}

##############################################################
# Main
##############################################################
require_root

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   Secure Boot + TPM2 LUKS enrollment — ${MACHINE}   ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

MODE="${1:-}"

case "$MODE" in
  --sb)        do_secureboot ;;
  --tpm2)      do_tpm2 ;;
  --wipe-tpm2) do_wipe_tpm2 ;;
  "")
    echo "What would you like to do?"
    echo "  1) Secure Boot key enrollment (needs UEFI Setup Mode)"
    echo "  2) TPM2 LUKS enrollment (needs Secure Boot active first)"
    echo "  3) Both (Step 1 now — you'll need to reboot before Step 2 takes effect)"
    echo "  4) Wipe TPM2 slots"
    echo "  q) Quit"
    echo
    read -rp "Choice: " choice
    case "$choice" in
      1) do_secureboot ;;
      2) do_tpm2 ;;
      3) do_secureboot; echo; warn "Reboot, confirm Secure Boot is ON, then re-run with --tpm2." ;;
      4) do_wipe_tpm2 ;;
      q|Q) exit 0 ;;
      *) err "Invalid choice."; exit 1 ;;
    esac
    ;;
  *)
    err "Unknown option: $MODE"
    echo "Usage: $0 [--sb | --tpm2 | --wipe-tpm2]"
    exit 1
    ;;
esac
