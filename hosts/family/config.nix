# hosts/family/config.nix
{ pkgs, lib, inputs, ... }:
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/secure-boot.nix
    ./hardware.nix
    ./boot.nix
    ../../profiles/niri.nix
    ../../modules/greetd.nix
    inputs.sops-nix.nixosModules.sops
  ];

  ############################################################
  # Secrets (SOPS)
  ############################################################
  #  sops = {
  #  defaultSopsFile = ../../secrets/shared.yaml;
  #  age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  #  secrets.openweathermap_api_key = {
  #    owner = "family";
  #    path  = "/run/secrets/openweathermap_api_key";
  #  };
  #  };

  ############################################################
  # Identity / Kernel
  ############################################################
  networking.hostName = "family";
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # Disable broken internal panel at DRM level — lid is permanently closed.
  # Prevents eDP-1 from being enumerated as a CRTC.
  boot.kernelParams = [ "video=eDP-1:d" ];

  ############################################################
  # Networking
  ############################################################
  # Required for WireGuard routing
  networking.firewall.checkReversePath = false;

  ############################################################
  # Bluetooth
  ############################################################
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  ############################################################
  # GPU — Intel UHD 620 (Kaby Lake GT2)
  # intel-media-driver required for VA-API; without it Steam CEF falls back
  # to software rendering and shows a black window.
  ############################################################
  hardware.graphics = {
    enable      = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  services.xserver.xkb = { layout = "us"; };

  # ProtonVPN WireGuard — disabled until config file is in place.
  # To enable: add ../../modules/protonvpn.nix to imports, set protonvpn.configFile,
  # add sudo rules, and enable waybar.protonvpn in home/family/waybar.nix.

  ############################################################
  # Printing
  ############################################################
  services.printing.enable = true;

  ############################################################
  # Audio — PipeWire
  ############################################################
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable            = true;
    alsa.enable       = true;
    alsa.support32Bit = true;
    pulse.enable      = true;
  };

  ############################################################
  # Users
  ############################################################
  users.users.family = {
    isNormalUser = true;
    description  = "family";
    shell        = pkgs.zsh;
    extraGroups  = [ "networkmanager" "wheel" ];
  };

  # Override base default (zsh) — prepko uses bash on this machine
  users.users.prepko.shell = lib.mkForce pkgs.bash;

  ############################################################
  # Programs
  ############################################################
  programs.firefox = {
    enable = true;
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
  };

  # Lid is closed permanently (broken screen) — don't suspend on lid events
  services.logind.lidSwitch = "ignore";

  ############################################################
  # System packages
  ############################################################
  environment.systemPackages = with pkgs; [
    featherpad
    wget
    git
    ghostty
  ];
}
