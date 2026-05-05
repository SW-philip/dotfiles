# Secure Boot + TPM2 LUKS Auto-Unlock Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable Secure Boot via lanzaboote on both hosts, bind LUKS auto-unlock to TPM2 PCR7 (Secure Boot state), and replace Plymouth theme with blahaj shark.

**Architecture:** lanzaboote replaces systemd-boot as the EFI stub and signs kernels/initrds on every rebuild. TPM2 is enrolled into each LUKS device using `systemd-cryptenroll --tpm2-pcrs=7`, binding disk unlock to the Secure Boot state measured in PCR7. Passphrase slot is preserved as recovery fallback.

**Tech Stack:** lanzaboote v0.4.1 (already in flake), sbctl, systemd-cryptenroll, tpm2-tools, `pkgs.plymouth-blahaj-theme`

---

## Task 1: Activate lanzaboote on Surface

**Files:**
- Modify: `hosts/surface/boot.nix`

**Step 1: Edit boot.nix**

Replace the existing `boot.loader.systemd-boot.enable = true;` line:

```nix
# hosts/surface/boot.nix
{ lib, ... }:

{
  imports = [ ../../modules/plymouth.nix ];

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
  };
  boot.initrd.systemd.enable = true;
  boot.initrd.kernelModules = [ "i915" ];

  # Cosmetic / quiet boot
  boot.kernelParams = lib.mkAfter [
    "quiet" "splash" "loglevel=0"
    "rd.systemd.show_status=false"
    "systemd.show_status=false"
    "vt.handoff=7"
  ];
}
```

**Step 2: Add sbctl to Surface system packages**

Open `hosts/surface/config.nix` and add `pkgs.sbctl` to `environment.systemPackages`. If there is no systemPackages list yet, add:

```nix
environment.systemPackages = with pkgs; [ sbctl ];
```

**Step 3: Rebuild (do NOT switch yet — just build to confirm no errors)**

```bash
sudo nixos-rebuild build --flake .#surface
```

Expected: build succeeds, no errors.

**Step 4: Switch**

```bash
sudo nixos-rebuild switch --flake .#surface
```

Expected: system switches. Boot entries are now signed by lanzaboote. Secure Boot is still OFF in firmware — system boots normally.

**Step 5: Verify lanzaboote is active**

```bash
sbctl status
```

Expected output shows `Installed: ✓` but `Secure Boot: disabled` (that's correct — keys not enrolled yet).

**Step 6: Commit**

```bash
git add hosts/surface/boot.nix hosts/surface/config.nix
git commit -m "feat(surface): activate lanzaboote for Secure Boot"
```

---

## Task 2: Activate lanzaboote on Desktop

**Files:**
- Modify: `hosts/desktop/boot.nix`
- Modify: `hosts/desktop/config.nix` (add sbctl)

**Step 1: Edit boot.nix**

```nix
# hosts/desktop/boot.nix
{ lib, ... }:

{
  imports = [ ../../modules/plymouth.nix ];

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
  };
  boot.initrd.systemd.enable = true;

  # Cosmetic / quiet boot
  boot.kernelParams = lib.mkAfter [
    "8250.nr_uarts=0"
    "quiet" "splash" "loglevel=0"
    "rd.systemd.show_status=false"
    "systemd.show_status=false"
    "vt.handoff=7"
    "delayacct"
  ];
}
```

**Step 2: Add sbctl to Desktop system packages**

Add `pkgs.sbctl` to `environment.systemPackages` in `hosts/desktop/config.nix`.

**Step 3: Build and switch**

```bash
sudo nixos-rebuild switch --flake .#desktop
```

Expected: build succeeds, system switches.

**Step 4: Commit**

```bash
git add hosts/desktop/boot.nix hosts/desktop/config.nix
git commit -m "feat(desktop): activate lanzaboote for Secure Boot"
```

---

## Task 3: Configure TPM2 + LUKS PCR7 on Desktop

The Surface already has `security.tpm2` and `tpm2-pcrs=7` configured. Desktop is missing both.

**Files:**
- Modify: `hosts/desktop/hardware.nix`

**Step 1: Add TPM2 system config and PCR7 binding**

Add the `security.tpm2` block and `tpm2-pcrs=7` to both LUKS devices:

```nix
############################################################
# TPM2
############################################################
security.tpm2 = {
  enable = true;
  pkcs11.enable = true;
  tctiEnvironment.enable = true;
};
```

Then for each LUKS device, add `"tpm2-pcrs=7"` to `crypttabExtraOpts`:

```nix
boot.initrd.luks.devices."luks-YOUR-DESKTOP-ROOT-UUID" = {
  device = "/dev/disk/by-uuid/YOUR-DESKTOP-ROOT-UUID";
  allowDiscards = true;
  crypttabExtraOpts = [ "tpm2-device=auto" "tpm2-pcrs=7" ];
};

boot.initrd.luks.devices."luks-YOUR-DESKTOP-SRV-UUID" = {
  device = "/dev/disk/by-uuid/YOUR-DESKTOP-SRV-UUID";
  allowDiscards = false;
  crypttabExtraOpts = [ "tpm2-device=auto" "tpm2-pcrs=7" ];
};
```

**Step 2: Rebuild Desktop**

```bash
sudo nixos-rebuild switch --flake .#desktop
```

**Step 3: Commit**

```bash
git add hosts/desktop/hardware.nix
git commit -m "feat(desktop): add TPM2 config and LUKS PCR7 binding"
```

---

## Task 4: Replace Plymouth theme with blahaj

**Files:**
- Modify: `modules/plymouth.nix`

**Step 1: Replace the module contents**

```nix
# modules/plymouth.nix
{ pkgs, ... }:

{
  boot.consoleLogLevel = 0;

  boot.initrd = {
    verbose = false;
    systemd.packages = [ pkgs.plymouth ];
    systemd.services.plymouth.enable = true;
  };

  boot.plymouth = {
    enable = true;
    theme = "blahaj";
    themePackages = [ pkgs.plymouth-blahaj-theme ];
  };
}
```

**Step 2: Rebuild Surface (or Desktop — module is shared)**

```bash
sudo nixos-rebuild switch --flake .#surface
```

Expected: Plymouth theme switches to blahaj on next boot.

**Step 3: Commit**

```bash
git add modules/plymouth.nix
git commit -m "feat: replace plymouth theme with blahaj shark"
```

---

## Task 5: Enroll Secure Boot Keys — Surface (manual, one-time)

> These steps are done at the machine. Cannot be automated.

**Step 1: Generate keys**

```bash
sudo sbctl create-keys
```

Expected: keys created under `/etc/secureboot/`.

**Step 2: Verify all EFI binaries are signed**

```bash
sudo sbctl verify
```

Expected: all entries show `✓ Signed`. If anything shows unsigned, run:
```bash
sudo sbctl sign-all
```

**Step 3: Reboot into UEFI firmware**

Enter BIOS/UEFI setup (usually Del, F2, or F12 on boot). Navigate to Secure Boot settings and enable **Setup Mode** (this clears factory keys — required to enroll custom keys).

**Step 4: Enroll keys (back in NixOS)**

```bash
sudo sbctl enroll-keys --microsoft
```

The `--microsoft` flag keeps Microsoft's UEFI keys alongside your custom keys. Required for hardware option ROMs (e.g., NVMe controllers) that are signed by Microsoft.

Expected: `Enrolled keys to EFI`

**Step 5: Enable Secure Boot in firmware**

Reboot → UEFI → enable Secure Boot → save → boot into NixOS.

**Step 6: Verify Secure Boot is active**

```bash
sbctl status
```

Expected:
```
Installed:    ✓
Secure Boot:  ✓ enabled
```

---

## Task 6: Enroll TPM2 into LUKS — Surface (manual, one-time)

> Run after Secure Boot is confirmed active (Task 5 complete).

**Step 1: Enroll TPM2 for cryptroot**

```bash
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=7 \
  /dev/disk/by-uuid/YOUR-SURFACE-LUKS-UUID
```

You will be prompted for your existing LUKS passphrase to authorize adding a new key slot.

Expected: `New TPM2 token enrolled as key slot N.`

**Step 2: Test auto-unlock**

```bash
sudo reboot
```

Expected: system boots without any passphrase prompt, LUKS unlocks automatically.

**Step 3: Verify TPM2 slot is present**

After reboot:
```bash
sudo systemd-cryptenroll /dev/disk/by-uuid/YOUR-SURFACE-LUKS-UUID
```

Expected: shows both a passphrase slot and a `tpm2` slot.

---

## Task 7: Enroll Secure Boot Keys — Desktop (manual, one-time)

Same process as Task 5 but on the desktop machine. Keys are generated fresh per-host (each machine has its own `/etc/secureboot`).

**Step 1:** `sudo sbctl create-keys`
**Step 2:** `sudo sbctl verify` (sign-all if needed)
**Step 3:** Reboot → UEFI → Setup Mode
**Step 4:** `sudo sbctl enroll-keys --microsoft`
**Step 5:** UEFI → enable Secure Boot → reboot
**Step 6:** `sbctl status` → confirm `Secure Boot: ✓ enabled`

---

## Task 8: Enroll TPM2 into LUKS — Desktop (manual, one-time)

Desktop has two LUKS devices — enroll both.

**Step 1: Enroll root device**

```bash
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=7 \
  /dev/disk/by-uuid/YOUR-DESKTOP-ROOT-UUID
```

**Step 2: Enroll backup device**

```bash
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=7 \
  /dev/disk/by-uuid/YOUR-DESKTOP-SRV-UUID
```

**Step 3: Reboot and verify auto-unlock**

```bash
sudo reboot
```

Expected: both LUKS volumes unlock without passphrase.

---

## Recovery Notes

If Secure Boot keys change or Secure Boot is disabled, PCR7 changes and TPM2 refuses to release the LUKS key. To recover:

1. Boot normally, enter LUKS passphrase manually
2. Wipe the old TPM2 slot: `sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-uuid/<uuid>`
3. Re-enroll: `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-uuid/<uuid>`
