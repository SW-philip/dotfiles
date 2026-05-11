# modules/howdy.nix
# Facial recognition login via howdy (from unstable — not in 25.11).
#
# Camera setup: the Surface Pro 7+ uses Intel IPU6 which can't be read
# directly by OpenCV. libcamera CAN access the ov5693 front camera, so
# we bridge it into a v4l2loopback device (/dev/video100) that howdy reads.
#
# After rebuild:
#   sudo howdy add    (enroll face)
#   sudo howdy test   (verify)
{ pkgsUnstable, ... }:
let
  howdy   = pkgsUnstable.howdy;
  loopDev = "/dev/video100";

  # CAMERA BRIDGE — commented out pending recompile
  # libcam   = pkgs.libcamera;
  # gst      = pkgs.gst_all_1;
  # cameraBridge = pkgs.writeShellScript "howdy-camera-bridge" ''
  #   export GST_PLUGIN_PATH="${libcam}/lib/gstreamer-1.0:${gst.gst-plugins-base}/lib/gstreamer-1.0:${gst.gst-plugins-good}/lib/gstreamer-1.0"
  #   export LIBCAMERA_IPA_MODULE_PATH="${libcam}/lib/libcamera"
  #   export LIBCAMERA_IPA_PROXY_PATH="${libcam}/libexec/libcamera"
  #   exec ${gst.gstreamer}/bin/gst-launch-1.0 -v \
  #     libcamerasrc ! \
  #     video/x-raw,width=320,height=240,framerate=15/1 ! \
  #     videoconvert ! \
  #     video/x-raw,format=YUY2,width=320,height=240,framerate=15/1 ! \
  #     v4l2sink device=${loopDev}
  # '';
in
{
  # CAMERA BRIDGE — commented out pending recompile
  # boot.kernelModules        = [ "v4l2loopback" ];
  # boot.extraModulePackages  = [ config.boot.kernelPackages.v4l2loopback ];
  # boot.extraModprobeConfig  = ''
  #   options v4l2loopback devices=1 video_nr=100 card_label="Howdy Camera" exclusive_caps=1
  # '';

  # systemd.services.howdy-camera-bridge = {
  #   description = "Bridge IPU6 camera to v4l2loopback for howdy";
  #   wantedBy    = [ "multi-user.target" ];
  #   after       = [ "systemd-modules-load.service" ];
  #   serviceConfig = {
  #     ExecStart   = cameraBridge;
  #     Restart     = "on-failure";
  #     RestartSec  = "3s";
  #   };
  # };

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
    device_path = ${loopDev}
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
    control    = "sufficient";
    modulePath = "${howdy}/lib/security/pam_howdy.so";
    order      = 11500;
  };
  security.pam.services.sudo.rules.auth.howdy = {
    control    = "sufficient";
    modulePath = "${howdy}/lib/security/pam_howdy.so";
    order      = 11000;
  };

  environment.systemPackages = [ howdy ];
  users.users.prepko.extraGroups = [ "video" ];
}
