{ inputs, pkgs, lib, config, ... }:

{
  imports = [
    ./base.nix
    ../packages/fastfetch-desktop.nix
  ];

  home.pointerCursor.size = lib.mkForce 24;

  ########################################
  # Explicit flake attr for desktop nrs aliases
  ########################################
  programs.zsh.shellAliases = {
    nrs = lib.mkForce "sudo nixos-rebuild switch --flake .#desktop && sudo systemctl restart home-manager-prepko.service";
    nrb = lib.mkForce "sudo nixos-rebuild boot --flake .#desktop";
    nrt = lib.mkForce "sudo nixos-rebuild test --flake .#desktop";
  };

  xdg.configFile."hypr/monitor.conf".text = ''
    monitor = DP-4, 1920x1080@60, 0x0, 1.0
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
}
