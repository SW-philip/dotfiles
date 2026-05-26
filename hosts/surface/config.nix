{ inputs, config, pkgs, ... }:

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
    #  ../../modules/howdy.nix
    ../../modules/tailscale.nix
    ../../modules/protonvpn.nix
    ../../modules/sqlch.nix
    ./hardware.nix
    ./boot.nix
    ./features.nix
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
    secrets.protonvpn_ny_conf = { sopsFile = ../../secrets/shared.yaml; };
    secrets.protonvpn_au_conf = { sopsFile = ../../secrets/shared.yaml; };
    secrets.protonvpn_ca_conf = { sopsFile = ../../secrets/shared.yaml; };
  };

  ############################################################
  # ProtonVPN
  ############################################################
  protonvpn.configs = {
    protonvpn-ny = config.sops.secrets.protonvpn_ny_conf.path;
    protonvpn-au = config.sops.secrets.protonvpn_au_conf.path;
    protonvpn-ca = config.sops.secrets.protonvpn_ca_conf.path;
  };

  nix.settings.max-jobs = "auto";
  nix.distributedBuilds = true;
  nix.buildMachines = [{
    hostName = "desktop.local";
    systems = [ "x86_64-linux" ];
    sshUser = "prepko";
    sshKey = "/home/prepko/.ssh/id_ed25519";
    maxJobs = 6;
    supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
  }];
  nix.settings.builders-use-substitutes = true;

  ############################################################
  # Swap / zram
  ############################################################
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
  };

}
