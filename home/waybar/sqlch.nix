{ config, lib, pkgs, ... }:
let
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "rightBar" else "surfaceTopBar";

  scripts = ./scripts;
in {
  options.waybar.sqlch = {
    enable = lib.mkEnableOption "sqlch radio status and controls";
  };

  config = lib.mkIf config.waybar.sqlch.enable {
    programs.waybar.settings.${bar}."custom/sqlch" = {
      exec = "${scripts}/waybar-sqlch --status";
      on-click        = "${scripts}/sqlch-popup-toggle";
      on-click-right  = "${scripts}/waybar-sqlch --stop  && pkill -RTMIN+8 waybar";
      on-click-middle = "${scripts}/cava-toggle";
      on-scroll-up    = "${scripts}/waybar-sqlch --next  && pkill -RTMIN+8 waybar";
      on-scroll-down  = "${scripts}/waybar-sqlch --prev  && pkill -RTMIN+8 waybar";
      smooth-scrolling-threshold = 3;
      signal = 8;
      interval = "once";
      return-type = "json";
    };
  };
}
