# modules/howdy.nix
# Facial recognition login via howdy (from unstable — not in 25.11).
# After rebuild: sudo howdy add    (enroll face)
# To test:       sudo howdy test
# Camera note: uses ov5693 at /dev/video32 (likely front camera).
#   If face recognition fails entirely, try device_path = /dev/video8.
#   IR camera (ov7251) is not functional on this kernel — power supplier unresolved.
{ pkgsUnstable, ... }:
let
  howdy = pkgsUnstable.howdy;
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/howdy         0755 root root -"
    "d /var/lib/howdy/models  0700 root root -"
    "d /var/log/howdy         0755 root root -"
  ];

  environment.etc."howdy/config.ini".text = ''
    [core]
    detection_notice = false
    timeout_notice = true
    no_confirmation = false
    suppress_unknown = false
    abort_if_ssh = true
    abort_if_lid_closed = false
    disabled = false
    use_cnn = false
    workaround = pam

    [video]
    certainty = 3.5
    timeout = 5
    device_path = /dev/video32
    warn_no_device = true
    max_height = 240
    frame_width = -1
    frame_height = -1
    dark_threshold = 60
    recording_plugin = opencv
    device_format = v4l2
    force_mjpeg = false
    exposure = -1
    device_fps = -1
    rotate = 0

    [snapshots]
    save_failed = false
    save_successful = false

    [debug]
    end_report = false
  '';

  # Insert howdy before password check in both greetd and sudo.
  # sufficient: on success → done; on failure → continue to pam_unix (password fallback).
  security.pam.services.greetd.rules.auth.howdy = {
    control = "sufficient";
    modulePath = "${howdy}/lib/security/pam_howdy.so";
    order = 11500;
  };
  security.pam.services.sudo.rules.auth.howdy = {
    control = "sufficient";
    modulePath = "${howdy}/lib/security/pam_howdy.so";
    order = 11000;
  };

  environment.systemPackages = [ howdy ];
  users.users.prepko.extraGroups = [ "video" ];
}
