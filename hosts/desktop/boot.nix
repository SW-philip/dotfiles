{ lib, ... }:

{
  imports = [ ../../modules/plymouth.nix ];

  boot.loader.timeout = 0;
  boot.initrd.systemd.enable = true;
  boot.kernelParams = lib.mkAfter [
    "8250.nr_uarts=0"
    "quiet" "loglevel=0"
    "rd.systemd.show_status=false"
    "systemd.show_status=false"
    "vt.handoff=7"
    "delayacct"
  ];
}
