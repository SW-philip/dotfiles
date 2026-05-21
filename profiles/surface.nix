{ lib, pkgs, ... }:
{
  ############################################################
  # Nix / Lix — experimental features
  # Lix 2.93.3 still requires nix-command and flakes to be listed explicitly.
  ############################################################
  nix.settings.experimental-features = lib.mkForce [ "nix-command" "flakes" ];

  ############################################################
  # Audio (PipeWire)
  ############################################################
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    wireplumber.enable = true;
  };

  ############################################################
  # Bluetooth
  ############################################################
  hardware.bluetooth.enable = true;

  ############################################################
  # GVfs — needed for Nemo to mount network shares (SMB etc.)
  ############################################################
  services.gvfs.enable = true;
  environment.systemPackages = with pkgs; [ gvfs sshfs ];

  ############################################################
  # Steam
  ############################################################
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
  };
}
