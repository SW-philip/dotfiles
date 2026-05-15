# hosts/desktop/gpu-nvidia.nix
# NVIDIA GTX 1660 drives both DP-4 and DP-3. Intel iGPU (card1) has no
# connected displays and is used solely for VA-API hardware decode.
# No PRIME offload — NVIDIA is the uncontested KMS master for its card.
{ config, pkgs, lib, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];

  # Intel graphics (Mesa + VA-API) — hardware decode for mpv, Firefox, etc.
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
    # Required on desktop: pairs with NVreg_PreserveVideoMemoryAllocations
    # and prevents P-state drops causing missed vblanks during idle repaints.
    powerManagement.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # No PRIME: both monitors are on the NVIDIA card. Intel loads via i915
    # for VA-API but is not a DRM primary/offload participant.
  };

  boot.kernelParams = lib.mkAfter [
    "nvidia-drm.modeset=1"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "nvidia.NVreg_EnableGpuFirmware=0"   # disable GSP — fixes Turing Wayland stalls
  ];

  # Load i915 early for VA-API availability; not a PRIME dependency anymore
  boot.initrd.kernelModules = [ "i915" ];

  services.udev.extraRules = ''
    KERNEL=="card*", KERNELS=="0000:01:00.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/nvidia-gpu"
  '';

  environment.sessionVariables = {
    # Intel VA-API for video decode (mpv, Firefox, etc.)
    LIBVA_DRIVER_NAME = "iHD";
    # Force NVIDIA's GLX for xwayland-satellite (X11 apps under niri)
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    NVD_BACKEND               = "auto";
  };

  programs.steam.enable = true;
  programs.steam.remotePlay.openFirewall = true;
}
