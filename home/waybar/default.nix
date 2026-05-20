{ config, pkgs, lib, ... }:

let
  isDesktop = config.myConfig.isDesktop;
  p = import ../../themes/Rose-Pine/main/palette-main.nix;

  chooseModeExec = pkgs.writeShellScript "choose-mode" ''
    export PATH="${pkgs.lib.makeBinPath [ pkgs.jq pkgs.coreutils ]}:$PATH"
    THEME=$(cat "$HOME/.local/state/theme" 2>/dev/null || echo "main")

    case "$THEME" in
      main|moon|dawn|light|lilac-juniper|dark)
        case "$THEME" in
          moon)          L=moon ;;
          dawn|light)    L=dawn ;;
          lilac-juniper) L="lilac·juniper" ;;
          *)             L=main ;;
        esac
        _s() {
          if [ "$1" = "$L" ]; then
            printf '<span foreground="${p.IRIS}"><b>%s</b></span>' "$1"
          else
            printf '<span foreground="${p.MUTED}">%s</span>' "$1"
          fi
        }
        TIP="$(_s main)  →  $(_s moon)  →  $(_s dawn)  →  $(_s "lilac·juniper")"
        ;;
      *)
        TIP="<span foreground=\"${p.IRIS}\">$THEME</span>"
        ;;
    esac

    jq -cn --arg text "󰔎" --arg tip "$TIP" '{text: $text, tooltip: $tip}'
  '';
in
{
  imports = [
    ./cpu_temp.nix
    ./battery.nix
    ./clock.nix
    ./bluetooth.nix
    ./netstatus.nix
    ./volume.nix
    ./weather.nix
    ./mpris.nix
    ./sqlch.nix
    ./wleave.nix
    ./uniremote.nix
    ./powerprofile.nix
    ./idle-inhibit.nix
    ./dnd.nix
    ./btrfs.nix
    ./sleep-drain.nix
    ./flake-drift.nix
    ./perf.nix
    ./rotation-lock.nix
  ];

  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings = {
      # ── Desktop Bars ──────────────────────────────────────────────────
      leftBar = lib.mkIf isDesktop {
        name = "top-left";
        layer = "top";
        position = "top";
        output = "DP-4";
        height = 46;
        modules-left   = [ "niri/workspaces" ];
        modules-center = [ "custom/clock" "custom/weather" ];
      };

      leftBottomBar = lib.mkIf isDesktop {
        name = "bottom-left";
        layer = "top";
        position = "bottom";
        output = "DP-4";
        height = 46;
        modules-left   = [ "group/system-stats" "group/storage" ];
        modules-right  = [ "group/toggles" "group/actions" ];
        "group/system-stats" = {
          orientation = "horizontal";
          drawer = { transition-duration = 300; transition-left-to-right = true; };
          modules = [ "custom/battery" "custom/cpu_temp" "custom/perf" ];
          "on-scroll-up" = "";
          "on-scroll-down" = "";
        };
        "group/storage" = {
          orientation = "horizontal";
          drawer = { transition-duration = 300; transition-left-to-right = true; };
          modules = [ "custom/btrfs" "custom/flake-drift" ];
          "on-scroll-up" = "";
          "on-scroll-down" = "";
        };
        "group/toggles" = {
          orientation = "horizontal";
          drawer = { transition-duration = 300; transition-left-to-right = false; };
          modules = [ "custom/utilities-handle" "custom/power_profile" "custom/idle_inhibit" "custom/dnd" "custom/choose_mode" ];
          "on-scroll-up" = "";
          "on-scroll-down" = "";
        };
        "custom/utilities-handle" = {
          format = "󰙴";
          tooltip-format = "System utilities";
        };
        "group/actions" = {
          orientation = "horizontal";
          drawer = { transition-duration = 300; transition-left-to-right = false; };
          modules = [ "custom/wleave" "custom/uniremote" ];
          "on-scroll-up" = "";
          "on-scroll-down" = "";
        };
        "custom/choose_mode" = {
          exec = "${chooseModeExec}";
          on-click = "toggle-theme";
          on-click-right = "python3 ${./scripts/theme-picker.py}";
          return-type = "json";
          interval = "once";
        };
      };

      rightBar = lib.mkIf isDesktop {
        name = "right";
        layer = "top";
        position = "top";
        output = "DP-3";
        height = 46;
        modules-left   = [ "niri/workspaces" ];
        modules-center = [ "custom/sqlch" "custom/mpris" ];
        modules-right  = [ "group/connectivity" "tray" "custom/volume" ];
        "group/connectivity" = {
          orientation = "horizontal";
          modules = [ "custom/bluetooth" "custom/network" ];
        };
      };

      # ── Surface Bars ──────────────────────────────────────────────────
      surfaceTopBar = lib.mkIf (!isDesktop) {
        name = "surface-top";
        layer = "top";
        position = "top";
        output = "eDP-1";
        height = 46;
        modules-left   = [ "niri/workspaces" ];
        modules-center = [ "custom/weather" ];
        modules-right  = [ "custom/mpris" "custom/volume" "custom/sqlch" ];
      };

      surfaceBottomBar = lib.mkIf (!isDesktop) {
        name = "surface-bottom";
        layer = "top";
        position = "bottom";
        output = "eDP-1";
        height = 45;
        modules-left   = [ "group/system-stats" "group/storage" ];
        modules-center = [ "custom/clock" ];
        modules-right  = [ "group/connectivity" "tray" "group/toggles" "group/actions" ];
        "group/system-stats" = {
          orientation = "horizontal";
          drawer = { transition-duration = 300; transition-left-to-right = true; };
          modules = [ "custom/battery" "custom/cpu_temp" "custom/perf" ];
          "on-scroll-up" = "";
          "on-scroll-down" = "";
        };
        "group/storage" = {
          orientation = "horizontal";
          drawer = { transition-duration = 300; transition-left-to-right = true; };
          modules = [ "custom/btrfs" "custom/flake-drift" ];
          "on-scroll-up" = "";
          "on-scroll-down" = "";
        };
        "group/connectivity" = {
          orientation = "horizontal";
          modules = [ "custom/bluetooth" "custom/network" ];
        };
        "group/toggles" = {
          orientation = "horizontal";
          drawer = { transition-duration = 300; transition-left-to-right = false; };
          modules = [ "custom/utilities-handle" "custom/idle_inhibit" "custom/power_profile" "custom/dnd" "custom/rotation_lock" "custom/choose_mode" ];
          "on-scroll-up" = "";
          "on-scroll-down" = "";
        };
        "custom/utilities-handle" = {
          format = "󰙴";
          tooltip-format = "System utilities";
        };
        "custom/choose_mode" = {
          exec = "${chooseModeExec}";
          on-click = "toggle-theme";
          on-click-right = "python3 ${./scripts/theme-picker.py}";
          return-type = "json";
          interval = "once";
        };
        "group/actions" = {
          orientation = "horizontal";
          drawer = { transition-duration = 300; transition-left-to-right = false; };
          modules = [ "custom/wleave" "custom/uniremote" ];
          "on-scroll-up" = "";
          "on-scroll-down" = "";
        };
      };
    };
  };

  # ── Systemd Service Overrides ─────────────────────────────────────
  systemd.user.services.waybar = {
    Unit = {
      Description = lib.mkForce "Waybar status bar";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Environment = [
        "PATH=${pkgs.lib.makeBinPath [
          pkgs.bash
          pkgs.bluez
          pkgs.bemenu
          pkgs.coreutils
          pkgs.procps
          pkgs.util-linux
          pkgs.jq
          pkgs.python3
          pkgs.gnused
          pkgs.gawk
          pkgs.gnugrep
          pkgs.findutils
        ]}:${config.home.homeDirectory}/.config/waybar/scripts:${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/run/wrappers/bin"

        "XDG_CURRENT_DESKTOP=niri"
        "XDG_SESSION_TYPE=wayland"
        "GIO_USE_VFS=local"
        "G_MESSAGES_DEBUG=none"
        "GTK_THEME=rose-pine-moon"
        "DCONF_PROFILE=/dev/null"
      ];
      ExecStart = lib.mkForce "${pkgs.waybar}/bin/waybar";
      Restart = lib.mkForce "on-failure";
      RestartSec = 2;
    };
  };

  # ── File Resources ────────────────────────────────────────────────
  xdg.configFile."theme/palette.sh".source = ../../themes/Rose-Pine/main/palette-main.nix;
  xdg.configFile."waybar/snark.json".source = ./snark.json;
  xdg.configFile."waybar/scripts" = {
    source = ./scripts;
    recursive = true;
  };

  xdg.configFile."systemd/user/waybar.service.d/session-guard.conf".text = ''
    [Unit]
    ConditionEnvironment=XDG_SESSION_DESKTOP=niri
  '';

  # ── Module Enablement ─────────────────────────────────────────────
  waybar = {
    cpu_temp.enable = true;
    battery.enable = true;
    clock.enable = true;
    bluetooth.enable = true;
    netstatus.enable = true;
    volume.enable = true;
    weather.enable = true;
    mpris.enable = true;
    sqlch.enable = true;
    wleave.enable = true;
    uniremote.enable = true;
    powerprofile.enable = true;
    idle_inhibit.enable = true;
    dnd.enable = true;
    btrfs.enable = true;
    sleepDrain.enable = true;
    flake-drift.enable = true;
    perf.enable = true;
    rotation_lock.enable = true;
  };
}
