{ inputs, pkgs, lib, config, ... }:

{
  imports = [
    ./base.nix
    ../packages/fastfetch-desktop.nix
    inputs.ignis.homeManagerModules.default
  ];

  home.pointerCursor.size = lib.mkForce 24;

  xdg.configFile."hypr/monitor.conf".text = ''
    monitor = DP-4, 1920x1080@60, 0x0, 1.0
    monitor = DP-3, 1920x1080@60, 1920x0, 1.0
    monitor = eDP-1, disabled
    monitor = , preferred, auto, 1
  '';

  myConfig.isDesktop = true;

  programs.ignis = {
    enable = true;
    services.audio.enable   = true;
    services.network.enable  = true;
    services.bluetooth.enable = true;
  };

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
}
