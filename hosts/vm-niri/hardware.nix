# hosts/vm-niri/hardware.nix
# Virtual hardware for QEMU/KVM — build-vm compatible
# Used by: nixos-rebuild build-vm --flake .#vm-niri
{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    # Provides virtualisation.{diskSize,memorySize,cores,graphics,qemu.*} options
    (modulesPath + "/virtualisation/qemu-vm.nix")
  ];

  ############################################################
  # Boot
  ############################################################
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  # virtio_gpu must be in initrd: DRM device must exist before greetd starts
  boot.initrd.kernelModules = [ "virtio_gpu" ];
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_net" "virtio_scsi" ];

  ############################################################
  # Filesystem (build-vm provisions this automatically)
  ############################################################
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  ############################################################
  # build-vm VM parameters
  ############################################################
  virtualisation = {
    diskSize  = 20480;   # 20 GB
    memorySize = 4096;   # 4 GB
    cores     = 4;

    # Disable default virtio-vga so we can replace it with virtio-gpu-gl
    graphics = false;

    qemu.options = [
      # virtio-gpu-gl: Gallium virgl — full DRM/3D via host GPU
      # virtio-gpu-gl IS the virgl/OpenGL-capable variant; virgl=on no longer exists
      "-device virtio-gpu-gl,xres=1920,yres=1080"

      # SPICE display with host OpenGL passthrough; auto-opens remote-viewer
      "-display spice-app,gl=on"

      # SPICE agent channel — clipboard passthrough + dynamic resolution
      "-device virtio-serial"
      "-chardev spicevmc,id=vdagent,debug=0,name=vdagent"
      "-device virtserialport,chardev=vdagent,name=com.redhat.spice.0"

      # VirtIO audio via SPICE
      "-audiodev spice,id=audio0"
      "-device virtio-sound-pci,audiodev=audio0"

      # Tablet: proper relative→absolute pointer translation in Wayland
      "-device virtio-tablet"

      # VirtIO RNG: faster entropy, useful during boot
      "-device virtio-rng-pci"
    ];
  };
}
