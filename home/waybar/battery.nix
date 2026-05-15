{ config, pkgs, lib, ... }:

let
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";

  batteryScript = pkgs.writeShellScriptBin "battery" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/battery.sh "$@"
  '';
in
{
  options.waybar.battery.enable = lib.mkEnableOption "battery module";

  config = lib.mkIf config.waybar.battery.enable {
    home.packages = [ batteryScript ];

    programs.waybar.settings.${bar}."custom/battery" = {
      exec = "${batteryScript}/bin/battery";
      return-type = "json";
      interval = 30;

      format = "{}";
      tooltip = true;
      tooltip-format = "{}";
      on-click = "";
    };
  };
}
