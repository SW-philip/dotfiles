{ inputs, pkgs, lib, config, ... }:

{
  # Import the shared base configuration and the Hyprland‑specific bits
  imports = [
    ./base.nix
    ../packages/fastfetch-desktop.nix
  ];

  # Hyprland monitor layout – stored under $XDG_CONFIG_HOME/hypr/monitor.conf
  xdg.configFile."hypr/monitor.conf".text = ''
    monitor = DP-2, 1920x1080@60, 0x0, 1.0
    monitor = DP-3, 1920x1080@60, 1920x0, 1.0
    monitor = eDP-1, disabled
    monitor = , preferred, auto, 1
  '';

  myConfig.isDesktop = true;

  home.packages = with pkgs; [
    awww
    wl-screenrec
    ncspot
    wayland-utils
    swayosd
    ydotool
    vulkan-tools
    mesa-demos
    drm_info
    smartmontools
    dig
  ];

  # No extra user‑systemd services beyond what `base.nix` provides.
  # (Steam is handled system‑side in `gpu-nvidia.nix`.)
  # (Deluge is handled system‑side in `hosts/desktop/default.nix`.)
}
