{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  ############################################################
  # Initrd / Kernel modules
  ############################################################
  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" "coretemp" ];
  boot.extraModulePackages = [ ];

  ############################################################
  # Kernel (linux-surface forced in features.nix)
  ############################################################
  hardware.cpu.intel.updateMicrocode = true;

  ############################################################
  # TPM2
  ############################################################
  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
    tctiEnvironment.enable = true;
  };

  ############################################################
  # LUKS
  ############################################################
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/YOUR-SURFACE-LUKS-UUID";
    allowDiscards = true;
    crypttabExtraOpts = [
      "tpm2-device=auto"
      "tpm2-pcrs=7"
    ];
  };

  ############################################################
  # Filesystems
  ############################################################
  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" "noatime" ];
  };

  fileSystems."/home" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/YOUR-SURFACE-EFI-UUID";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
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
