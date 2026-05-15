{ lib, ... }:
{
  boot.initrd.kernelModules = [ "i915" ];

  boot.kernelParams = lib.mkAfter [
    "quiet" "splash" "loglevel=0"
    "rd.systemd.show_status=false"
    "systemd.show_status=false"
    "vt.handoff=7"
  ];
}
