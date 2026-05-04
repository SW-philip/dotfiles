# Secure Boot + TPM2 LUKS Auto-Unlock Design

**Date:** 2026-03-20
**Hosts:** surface (primary), desktop (secondary)
**Status:** Approved

---

## Goals

1. Enable Secure Boot on both hosts using lanzaboote (custom keys, not shim-only)
2. Auto-unlock LUKS via TPM2 bound to PCR7 (Secure Boot state) — no passphrase prompt on boot
3. Replace Plymouth boot splash with `plymouth-blahaj-theme` (Blåhaj shark)
4. Add steam-girl Plasma splash screen from https://github.com/73XAZ-lexaz/steam-girl-splash-theme

---

## Approach

**lanzaboote** replaces systemd-boot as the EFI stub. It auto-signs kernels and initrds on every rebuild. Keys are stored in `/etc/secureboot` and managed with `sbctl`.

TPM2 LUKS binding uses `systemd-cryptenroll --tpm2-pcrs=7`. PCR7 measures the Secure Boot policy — if Secure Boot is disabled or keys change, the TPM refuses to release the LUKS key. Passphrase slot is preserved as recovery fallback.

---

## NixOS Config Changes

### `hosts/surface/boot.nix`
- Remove `boot.loader.systemd-boot.enable = true`
- Add `boot.loader.systemd-boot.enable = lib.mkForce false`
- Add `boot.lanzaboote.enable = true` and `boot.lanzaboote.pkiBundle = "/etc/secureboot"`

### `hosts/desktop/boot.nix`
- Same lanzaboote changes as surface

### `hosts/surface/hardware.nix`
- Already correct: `security.tpm2.enable = true`, `tpm2-pcrs=7` on LUKS device
- Add `sbctl` to system packages (or a shared module)

### `hosts/desktop/hardware.nix`
- Add `security.tpm2` block (enable = true, pkcs11, tctiEnvironment)
- Add `tpm2-pcrs=7` to both LUKS device crypttabExtraOpts
- Add `sbctl` to system packages

### `modules/plymouth.nix`
- Remove custom `hexagon-hud-theme` derivation
- Switch to `pkgs.plymouth-blahaj-theme` from nixpkgs

### Home Manager (surface + desktop profiles)
- Add Plasma splash screen config pointing to steam-girl theme
- Fetch theme via `fetchFromGitHub` from `73XAZ-lexaz/steam-girl-splash-theme`
- Install via `xdg.dataFile` into `~/.local/share/plasma/look-and-feel/`
- Set `programs.plasma.splash.theme` (or equivalent HM option)

---

## Manual Steps (per host, after rebuild)

These cannot be automated — must be done once per host:

1. `sudo sbctl create-keys` — generate Secure Boot keys
2. Reboot → UEFI firmware → enable **Setup Mode** (clears factory keys)
3. `sudo sbctl enroll-keys --microsoft` — enroll custom keys + Microsoft keys (for option ROMs)
4. Enable Secure Boot in UEFI firmware → save → reboot into NixOS
5. Verify Secure Boot is active: `sbctl status`
6. Enroll TPM2 into LUKS:
   - Surface: `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-uuid/YOUR-SURFACE-LUKS-UUID`
   - Desktop (root): `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-uuid/YOUR-DESKTOP-ROOT-UUID`
   - Desktop (backup): `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-uuid/YOUR-DESKTOP-SRV-UUID`
7. Reboot — LUKS unlocks automatically, no passphrase prompt

---

## Security Notes

- `--microsoft` flag keeps Microsoft keys enrolled alongside custom keys — required for hardware option ROMs (NVIDIA, NVMe controllers) to function correctly
- PCR7 binding means disabling Secure Boot or re-keying will lock the drive until passphrase is used and TPM is re-enrolled
- Passphrase slot (key slot 0) is never removed — always available as recovery

---

## Plymouth Theme

**Package:** `pkgs.plymouth-blahaj-theme`
**Theme name:** `blahaj`
Replaces the existing custom `hexagon_hud` derivation entirely.

---

## Plasma Splash Theme

**Source:** https://github.com/73XAZ-lexaz/steam-girl-splash-theme
**Type:** KDE Plasma look-and-feel splash screen (QML-based)
**Install location:** `~/.local/share/plasma/look-and-feel/steam-girl-splash-theme`
Configured via Home Manager for the `prepko` user on both hosts.
