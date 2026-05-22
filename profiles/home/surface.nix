{ inputs, pkgs, lib, config, ... }:
{
  imports = [
    ./base.nix
  ];

  ########################################
  # Surface HiDPI cursor override (base sets 48px; Surface needs 32px at 1.5x scale)
  ########################################
  home.pointerCursor.size = lib.mkForce 32;

  ########################################
  # Fix nrs alias — hostname surface != flake attr surface
  ########################################
  programs.zsh.shellAliases = {
    nrs = lib.mkForce "sudo nixos-rebuild switch --flake .#surface && sudo systemctl restart home-manager-prepko.service";
    nrb = lib.mkForce "sudo nixos-rebuild boot --flake .#surface";
    nrt = lib.mkForce "sudo nixos-rebuild test --flake .#surface";
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = lib.mkForce {
      color-scheme = "prefer-dark";
      cursor-theme = "BreezeX-RosePine-Linux";
      gtk-theme = "Adwaita-dark";
    };
  };

  ########################################
  # Surface-only packages
  ########################################
  home.packages = with pkgs; [
    pandora
    wvkbd           # virtual keyboard
    xournalpp       # stylus note-taking
    foliate         # ebook reader
    koreader        # ebook reader (alternative)
    yacreader       # comic reader
  ];

  ########################################
  # Screen auto-rotation
  # iio orientations → niri CCW transforms:
  #   normal    → normal  (landscape)
  #   bottom-up → 180     (upside-down landscape)
  #   right-up  → 270     (portrait, volume buttons on left)
  #   left-up   → 90      (portrait, volume buttons on right)
  ########################################
  systemd.user.services.niri-rotation = {
    Unit = {
      Description = "Auto-rotate niri output via iio-sensor-proxy";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "niri-rotation" ''
        ${pkgs.iio-sensor-proxy}/bin/monitor-sensor 2>/dev/null \
          | while IFS= read -r line; do
              case "$line" in
                *"normal"*)    ${pkgs.niri}/bin/niri msg output eDP-1 transform normal ;;
                *"bottom-up"*) ${pkgs.niri}/bin/niri msg output eDP-1 transform 180 ;;
                *"right-up"*)  ${pkgs.niri}/bin/niri msg output eDP-1 transform 270 ;;
                *"left-up"*)   ${pkgs.niri}/bin/niri msg output eDP-1 transform 90 ;;
              esac
            done
      '';
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  ########################################
  # On-screen keyboard — started/stopped by surface-kbd-monitor
  ########################################
  systemd.user.services.wvkbd = {
    Unit = {
      Description = "On-screen keyboard (wvkbd)";
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "wvkbd-launch" ''
        colors_file="$HOME/.config/wvkbd/colors.sh"
        WVKBD_ARGS=""
        if [ -f "$colors_file" ]; then
          . "$colors_file"
        fi
        exec ${pkgs.wvkbd}/bin/wvkbd-mobintl -L 300 $WVKBD_ARGS
      '';
      Restart = "on-failure";
      RestartSec = "2s";
    };
    # No WantedBy — demand-started by surface-kbd-monitor
  };

  ########################################
  # Type Cover keyboard monitor
  # Shows wvkbd when "Microsoft Surface Type Cover Keyboard"
  # disappears from /sys/class/input, hides it when it returns.
  ########################################
  systemd.user.services.surface-kbd-monitor = {
    Unit = {
      Description = "Show wvkbd when Surface Type Cover is detached";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "surface-kbd-monitor" ''
        SC="${pkgs.systemd}/bin/systemctl"

        kbd_present() {
          grep -qlF "Type Cover Keyboard" /sys/class/input/*/name 2>/dev/null
        }

        update() {
          if kbd_present; then
            $SC --user stop wvkbd.service 2>/dev/null || true
          else
            $SC --user start wvkbd.service 2>/dev/null || true
          fi
        }

        update

        ${pkgs.systemd}/bin/udevadm monitor --udev --property --subsystem-match=input \
          | ${pkgs.gawk}/bin/awk '
              /^UDEV/  { action=""; name=""; next }
              /^ACTION=/ { action = substr($0, 8) }
              /^NAME=/   { name = substr($0, 6); gsub(/"/, "", name) }
              /^$/       {
                if (name ~ /Type Cover Keyboard/) { print action; fflush() }
                action=""; name=""
              }
            ' \
          | while read -r _event; do
              sleep 0.3
              update
            done
      '';
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
