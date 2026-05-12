{ pkgs, pkgsUnstable, config, ... }:
let
  howdy    = pkgsUnstable.howdy;
  libcam   = pkgs.libcamera;
  gst      = pkgs.gst_all_1;
  loopDev  = "/dev/video100";
  frontCam = "_SB_.PC00.I2C2.CAMF";

  cameraBridge = pkgs.writeShellScript "howdy-camera-bridge" ''
    set -o pipefail
    export GST_PLUGIN_PATH="${libcam}/lib/gstreamer-1.0:${gst.gstreamer.out}/lib/gstreamer-1.0:${gst.gst-plugins-base}/lib/gstreamer-1.0:${gst.gst-plugins-good}/lib/gstreamer-1.0"
    export LIBCAMERA_IPA_MODULE_PATH="${libcam}/lib/libcamera"
    ${gst.gstreamer}/bin/gst-launch-1.0 \
      libcamerasrc camera-name='${frontCam}' ! \
      videoconvert ! videoscale ! videorate ! \
      'video/x-raw,format=BGR,width=320,height=240,framerate=30/1' ! \
      fdsink fd=1 | \
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

  systemd.services.howdy-camera-bridge = {
    description = "Bridge IPU6 front camera to v4l2loopback for howdy";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "systemd-modules-load.service" ];
    before      = [ "greetd.service" ];
    serviceConfig = {
      ExecStart  = cameraBridge;
      Restart    = "always";
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
