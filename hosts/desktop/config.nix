# hosts/desktop/config.nix
{ inputs, config, pkgs, ... }:

{
  ############################################################
  # Imports
  ############################################################
  imports = [
    # Profiles (system-wide)
    ../../profiles/base.nix
    ../../profiles/secure-boot.nix
    ../../profiles/desktop.nix
    ../../profiles/niri.nix

    # Hardware & boot
    ./hardware.nix
    ./boot.nix
    ./gpu-nvidia.nix

    # Services & modules
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
  };
}
