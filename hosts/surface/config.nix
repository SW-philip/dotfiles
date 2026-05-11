# hosts/surface/config.nix
{ inputs, pkgs, ... }:

{
  ############################################################
  # Imports
  ############################################################
  imports = [
    ../../profiles/base.nix
    ../../profiles/secure-boot.nix
    ../../profiles/surface.nix
    ../../profiles/niri.nix
    inputs.nixos-hardware.nixosModules.microsoft-surface-pro-intel
    inputs.sops-nix.nixosModules.sops
    ../../profiles/sops-shared.nix
    ../../modules/greetd.nix
    ../../modules/protonvpn.nix
    ../../modules/sqlch.nix
    ./hardware.nix
    ./boot.nix
    ./features.nix
    ./msmtp.nix
    ./power.nix
    ./gpu-intel.nix
  ];

  ############################################################
  # Host identity
  ############################################################
  networking.hostName = "surface";

  ############################################################
  # Secrets (SOPS)
  ############################################################
  sops = {
    defaultSopsFile = ../../secrets/surface.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  ############################################################
  # ProtonVPN — file-based like desktop; put server .conf files in
  # ~/.config/wireguard/ and the selection menu symlinks protonvpn.conf.
  ############################################################
  protonvpn.configFile = "/home/prepko/.config/wireguard/protonvpn.conf";
  

  ############################################################
  # Swap / zram
  ############################################################
  zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 100;
  };

}
