{ lib, ... }:
{
  # Surface-specific system configuration.
  # Hardware (GPU, microcode, graphics) lives in hosts/surface/{gpu-intel,hardware}.nix.
  # Touch/stylus (iptsd) is enabled by nixos-hardware.microsoft-surface-pro-intel.

  ############################################################
  # Nix / Lix — experimental features
  # Lix 2.93.3 still requires nix-command and flakes to be listed explicitly.
  ############################################################
  nix.settings.experimental-features = lib.mkForce [ "nix-command" "flakes" ];

  ############################################################
  # Bluetooth
  ############################################################
  hardware.bluetooth.enable = true;

  ############################################################
  # Steam
  ############################################################
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
  };
}
