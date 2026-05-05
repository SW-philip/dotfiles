# hosts/vm-niri/config.nix
# NixOS guest: Wayland/Niri on QEMU/KVM with virtio-gpu-gl (virgl)
{ pkgs, lib, ... }:
{
  imports = [
    ./hardware.nix
    ../../profiles/base.nix
    ../../profiles/niri.nix
    ../../modules/greetd.nix
  ];

  networking.hostName = "niri-vm";

  ############################################################
  # Users
  ############################################################
  users.users.prepko = {
    # Change on first login: passwd prepko
    initialPassword = "nixos";
    shell = lib.mkForce pkgs.bash;
  };

  ############################################################
  # QEMU / SPICE guest services
  ############################################################
  # Graceful shutdown, clock sync, filesystem passthrough
  services.qemuGuest.enable = true;

  # Clipboard passthrough + dynamic resolution from SPICE
  services.spice-vdagentd.enable = true;

  ############################################################
  # Graphics: Mesa with virgl Gallium driver
  ############################################################
  hardware.graphics = {
    enable = true;
    # mesa includes the virgl Gallium driver by default on nixpkgs
    extraPackages = [ pkgs.mesa ];
  };

  # Hint Mesa to use the virtio/virgl driver (auto-detected, but explicit is safer)
  environment.sessionVariables.MESA_LOADER_DRIVER_OVERRIDE = "virtio_gpu";

  ############################################################
  # Audio (PipeWire)
  ############################################################
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  ############################################################
  # Networking — allow password auth for convenience in local VM
  ############################################################
  services.openssh.settings.PasswordAuthentication = lib.mkForce true;

  ############################################################
  # Packages
  ############################################################
  environment.systemPackages = with pkgs; [
    foot            # Wayland-native terminal
    niri
    xwayland-satellite
    spice-vdagent
    mesa-demos      # glxinfo, glxgears — verify virgl renderer
    wayland-utils   # wayland-info — verify compositor
    git
    curl
    vim
  ];
}
