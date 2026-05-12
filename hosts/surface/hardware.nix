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

  # 1. Add v4l2loopback to the kernel modules to load at boot
  boot.kernelModules = [ "kvm-intel" "coretemp" "v4l2loopback" ];

  # 2. Add the actual package to the kernel's module path
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];

  # 3. Force the "Capture" capability and set the device ID
  boot.extraModprobeConfig = ''
    options v4l2loopback exclusive_caps=1 card_label="Surface Camera" video_nr=100
  '';

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
