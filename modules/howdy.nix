{ pkgs, pkgsUnstable, config, ... }:
let
  howdy    = pkgsUnstable.howdy;
  libcam   = pkgs.libcamera;
  loopDev  = "/dev/video100";
  # Camera index 2 = front camera (_SB_.PC00.I2C2.CAMF, ov5693).
  # CameraManager::get(id) has a race condition in libcamera 0.6.0 where
  # start() returns before enumeration completes. Index-based selection
  # (cameras()[n-1]) works because cam calls it later in its code path.
  #
  # cam outputs ABGR8888 (4 bytes/pixel). V4L2_PIX_FMT_ABGR32 maps to
  # AV_PIX_FMT_BGRA in ffmpeg. cam's --file opens/closes per frame, so a
  # FIFO with a write-end holder (fd 9) prevents spurious EOF to ffmpeg.
  cameraBridge = pkgs.writeShellScript "howdy-camera-bridge" ''
    export LIBCAMERA_IPA_MODULE_PATH="${libcam}/lib/libcamera/ipa"
    FIFO=/run/howdy-cam.fifo
    rm -f "$FIFO"
    mkfifo "$FIFO"
    cleanup() {
      exec 9>&- 2>/dev/null || true
      kill "$FFMPEG_PID" 2>/dev/null || true
      rm -f "$FIFO"
    }
    trap cleanup EXIT INT TERM
    ${pkgs.ffmpeg}/bin/ffmpeg -nostdin -loglevel error \
      -f rawvideo -pix_fmt bgra -video_size 320x240 \
      -i "$FIFO" \
      -f v4l2 -pix_fmt yuyv422 \
      ${loopDev} &
    FFMPEG_PID=$!
    exec 9>"$FIFO"
    ${libcam}/bin/cam \
      --camera 2 \
      --stream role=viewfinder,width=320,height=240 \
      --capture \
      --file="$FIFO" >/dev/null 2>/dev/null
    exec 9>&-
    wait "$FFMPEG_PID"
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
