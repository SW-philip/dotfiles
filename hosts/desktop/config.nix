{ inputs, config, pkgs, ... }:

{
  ############################################################
  # Imports
  ############################################################
  imports = [
    ../../profiles/base.nix
    ../../profiles/secure-boot.nix
    ../../profiles/desktop.nix
    ../../profiles/niri.nix

    ./hardware.nix
    ./boot.nix
    ./gpu-nvidia.nix

    ./services.nix
    inputs.sops-nix.nixosModules.sops
    ../../profiles/sops-shared.nix
    ../../modules/protonvpn.nix
    ../../modules/jellyfin.nix
    ../../modules/sqlch.nix
    ../../modules/greetd.nix
  ];

  ############################################################
  # Nix / Lix
  ############################################################
  nix.package = pkgs.lixPackageSets.stable.lix;

  ############################################################
  # Host identity
  ############################################################
  networking.hostName = "desktop";
  greetd.greeting = "Welcome back, Phil.";

  ############################################################
  # Secrets (SOPS)
  ############################################################
  sops = {
    defaultSopsFile = ../../secrets/shared.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.protonvpn_ny_conf = {};
    secrets.protonvpn_au_conf = {};
    secrets.protonvpn_ca_conf = {};
  };

  ############################################################
  # ProtonVPN
  ############################################################
  protonvpn.configs = {
    protonvpn-ny = config.sops.secrets.protonvpn_ny_conf.path;
    protonvpn-au = config.sops.secrets.protonvpn_au_conf.path;
    protonvpn-ca = config.sops.secrets.protonvpn_ca_conf.path;
  };
}
