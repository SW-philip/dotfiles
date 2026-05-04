# hosts/surface/boot.nix
{ lib, ... }:

{
  imports = [ ../../modules/plymouth.nix ];

  boot.initrd.systemd.enable = true;
  boot.initrd.kernelModules = [ "i915" ];

  # Cosmetic / quiet boot
  boot.kernelParams = lib.mkAfter [
    "quiet" "splash" "loglevel=0"
    "rd.systemd.show_status=false"
    "systemd.show_status=false"
    "vt.handoff=7"
  ];
}
