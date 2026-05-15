{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  ############################################################
  # Initrd / Kernel modules
  ############################################################
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" "tpm_tis" "tpm_crb" ];
  boot.kernelPackages = pkgs.linuxPackages_7_0;
  boot.extraModulePackages = [ ];

  ############################################################
  # LUKS
  ############################################################
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

  ############################################################
  # TPM2
  ############################################################
  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
    tctiEnvironment.enable = true;
  };

  ############################################################
  # Filesystems
  ############################################################
  fileSystems."/" = {
    device = "/dev/mapper/luks-YOUR-DESKTOP-ROOT-UUID";
    fsType = "btrfs";
    options = [ "subvol=@" ];
  };

  fileSystems."/home" = {
    device = "/dev/mapper/luks-YOUR-DESKTOP-ROOT-UUID";
    fsType = "btrfs";
    options = [ "subvol=@home" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/YOUR-DESKTOP-EFI-UUID";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  fileSystems."/mnt/backup" = {
    device = "/dev/mapper/luks-YOUR-DESKTOP-SRV-UUID";
    fsType = "btrfs";
    options = [ "defaults" "nofail" "x-systemd.device-timeout=10" ];
  };

  fileSystems."/srv" = {
    device = "/dev/mapper/luks-YOUR-DESKTOP-SRV-UUID";
    fsType = "btrfs";
    options = [ "subvol=srv" "compress=zstd" "noatime" "nofail" "x-systemd.device-timeout=10" ];
  };

  ############################################################
  # Swap
  ############################################################
  swapDevices = [ ];

  ############################################################
  # Platform
  ############################################################
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
