# modules/virt.nix
# Host-side QEMU/KVM + libvirtd + virt-manager
{ pkgs, ... }:
{
  ############################################################
  # Libvirt / KVM
  ############################################################
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
      # OVMF is bundled with QEMU on nixpkgs-unstable — no separate config needed
    };
  };

  programs.virt-manager.enable = true;

  # SPICE USB redirection (tablet / USB passthrough into VMs)
  virtualisation.spiceUSBRedirection.enable = true;

  ############################################################
  # User access
  ############################################################
  users.users.prepko.extraGroups = [ "libvirtd" "kvm" ];

  ############################################################
  # Packages
  ############################################################
  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer    # remote-viewer — SPICE client
    spice-gtk      # SPICE GTK widget / libraries
    virtiofsd      # host-side virtiofs daemon for shared folders
    qemu_kvm       # qemu-img, qemu-system-x86_64, etc.
  ];
}
