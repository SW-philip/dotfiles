{ lib, ... }:
{
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
