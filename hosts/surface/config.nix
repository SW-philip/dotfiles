# hosts/surface/config.nix
{ inputs, pkgs, config, ... }:

{
  ############################################################
  # Imports
  ############################################################
  imports = [
    ../../profiles/base.nix
    ../../profiles/secure-boot.nix
    ../../profiles/surface.nix
    ../../profiles/niri.nix
    ../../profiles/vpn-security.nix
    inputs.nixos-hardware.nixosModules.microsoft-surface-pro-intel
    inputs.sops-nix.nixosModules.sops
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
    secrets.protonvpn_conf = {};
    secrets.spotify_env = {
      sopsFile = ../../secrets/shared.yaml;
      owner = "prepko";
    };
    secrets.openweathermap_api_key = {
      sopsFile = ../../secrets/shared.yaml;
      owner = "prepko";
    };
  };

  ############################################################
  # ProtonVPN
  ############################################################
  protonvpn.configFile = config.sops.secrets.protonvpn_conf.path;
  

  ############################################################
  # Swap / zram
  ############################################################
  zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 100;
  };

}
