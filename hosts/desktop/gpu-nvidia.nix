# hosts/desktop/gpu-nvidia.nix
# Intel iGPU is primary (default for apps/VA-API/Vulkan).
# NVIDIA is used exclusively by Hyprland via AQ_DRM_DEVICES.
{ config, pkgs, lib, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];

  # Intel graphics (Mesa + VA-API) — default for everything except Hyprland
  hardware.graphics = {
    enable      = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver   # iHD — VA-API for UHD 630+
      intel-vaapi-driver   # i965 — fallback for older content paths
    ];
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # PRIME offload: Intel is primary DRM provider, NVIDIA is offload target
    prime = {
      offload.enable = true;
      intelBusId  = "PCI:0:2:0";   # 00:02.0 Intel UHD 630
      nvidiaBusId = "PCI:1:0:0";   # 01:00.0 GTX 1660
    };
  };

  boot.kernelParams = lib.mkAfter [
    "nvidia-drm.modeset=1"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
  ];

  # Load i915 early so Intel is the primary DRM device at boot
  boot.initrd.kernelModules = [ "i915" ];

  services.udev.extraRules = ''
    KERNEL=="card*", KERNELS=="0000:01:00.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/nvidia-gpu"
  '';

  environment.sessionVariables = {
    # Wayland cursor safety — smithay/wlroots both respect this on NVIDIA
    WLR_NO_HARDWARE_CURSORS = "1";
    # Hyprland compositor runs on NVIDIA; all other apps default to Intel
    AQ_DRM_DEVICES    = "/dev/dri/nvidia-gpu";
    # Intel VA-API for video decode (mpv, Firefox, etc.)
    LIBVA_DRIVER_NAME = "iHD";
    # NVIDIA render tuning (only applies when NVIDIA is actually rendering)
    __GL_GSYNC_ALLOWED  = "0";
    __GL_VRR_ALLOWED    = "0";
    __GL_SYNC_TO_VBLANK = "1";
    NVD_BACKEND         = "auto";
  };

  programs.steam.enable = true;
  programs.steam.remotePlay.openFirewall = true;
}
