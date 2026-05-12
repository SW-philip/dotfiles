# modules/howdy.nix
# Facial recognition login via howdy (from unstable).
{ pkgs, pkgsUnstable, config, ... }:
let
  howdy    = pkgsUnstable.howdy;
  libcam   = pkgs.libcamera;
  loopDev  = "/dev/video100";

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

    # 1. Clear any existing locks on the media device immediately before starting
    # This wins the race against WirePlumber/PipeWire.
    ${pkgs.psmisc}/bin/fuser -k /dev/media0 || true

    # 2. Launch FFmpeg to listen to the FIFO
    ${pkgs.ffmpeg}/bin/ffmpeg -nostdin -loglevel error \
      -f rawvideo -pix_fmt bgra -video_size 320x240 \
      -i "$FIFO" \
      -f v4l2 -pix_fmt yuyv422 \
      ${loopDev} &
    FFMPEG_PID=$!

    # 3. Hold the FIFO open so 'cam' doesn't cause EOF on every frame
    exec 9>"$FIFO"

    # 4. Start the libcamera stream.
    # Using index 1 based on our successful manual test for ov5693.
    ${libcam}/bin/cam \
      --camera 1 \
      --stream role=viewfinder,width=320,height=240 \
      --capture \
      --file="$FIFO" >/dev/null 2>/dev/null

    exec 9>&-
    wait "$FFMPEG_PID"
  '';
in
{
  # Ensure the loopback module is loaded with exclusive_caps for OpenCV compatibility.
  boot.kernelModules = [ "v4l2loopback" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=100 card_label="Howdy Camera" exclusive_caps=1
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

  # Required directories for Howdy's operation
  systemd.tmpfiles.rules = [
    "d /var/lib/howdy          0755 root root -"
    "d /var/lib/howdy/models   0700 root root -"
    "d /var/log/howdy          0755 root root -"
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
