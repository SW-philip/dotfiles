{ config, lib, pkgs, ... }:

let
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "rightBar" else "surfaceTopBar";
in {
  options.waybar.mpris = {
    enable = lib.mkEnableOption "MPRIS media status";
  };

  config = lib.mkIf config.waybar.mpris.enable {
    programs.waybar.settings.${bar}."custom/mpris" = {
      exec = "${config.xdg.configHome}/waybar/scripts/mpris_status.sh";
      on-click       = "${config.xdg.configHome}/waybar/scripts/mpris_notify.sh";
      on-click-right = "${config.xdg.configHome}/waybar/scripts/mpris_clear_track_cache.sh";
      interval = "once";
      signal = 8;
      return-type = "json";
    };
  };
}
