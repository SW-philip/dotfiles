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
{ pkgs, pkgsUnstable, config, ... }:
let
  howdy    = pkgsUnstable.howdy;
  libcam   = pkgs.libcamera;
  gst      = pkgs.gst_all_1;
  loopDev  = "/dev/video100";
  # Camera ID as reported by `cam --list` (front camera = CAMF)
  frontCam = "_SB_.PC00.I2C2.CAMF";

  # GStreamer 1.26.x v4l2sink fails to negotiate with v4l2loopback 0.15.3.
  # Workaround: pipe raw BGR frames from fdsink → ffmpeg → v4l2loopback.
  cameraBridge = pkgs.writeShellScript "howdy-camera-bridge" ''
    export GST_PLUGIN_PATH="${libcam}/lib/gstreamer-1.0:${gst.gst-plugins-base}/lib/gstreamer-1.0:${gst.gst-plugins-good}/lib/gstreamer-1.0"
    export LIBCAMERA_IPA_MODULE_PATH="${libcam}/lib/libcamera"
    ${gst.gstreamer}/bin/gst-launch-1.0 \
      libcamerasrc camera-name='${frontCam}' ! \
      videoconvert ! videoscale ! videorate ! \
      'video/x-raw,format=BGR,width=320,height=240,framerate=30/1' ! \
      fdsink fd=1 \
      2>/dev/null | \
    ${pkgs.ffmpeg}/bin/ffmpeg -nostdin -loglevel error \
      -f rawvideo -pix_fmt bgr24 -video_size 320x240 -r 30 \
      -i pipe:0 \
      -f v4l2 -pix_fmt yuyv422 \
      ${loopDev}
  '';
in
{
  # v4l2loopback kernel module — virtual V4L2 device that OpenCV can read.
  boot.kernelModules       = [ "v4l2loopback" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=100 card_label="Howdy Camera"
  '';

  # Bridge libcamera → v4l2loopback. Starts before greetd so the device is
  # ready at the login screen. Restarts automatically on failure.
  systemd.services.howdy-camera-bridge = {
    description = "Bridge IPU6 front camera to v4l2loopback for howdy";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "systemd-modules-load.service" ];
    before      = [ "greetd.service" ];
    serviceConfig = {
      ExecStart  = cameraBridge;
      Restart    = "on-failure";
      RestartSec = "3s";
    };
  };

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
    workaround = off

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
