{ config, pkgs, lib, ... }:

let
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";

  tempScript = pkgs.writeShellScriptBin "cpu_temp" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/cpu_temp.sh "$@"
  '';

in {
  options.waybar.cpu_temp.enable = lib.mkEnableOption "CPU Temperature module";

  config = lib.mkIf config.waybar.cpu_temp.enable {
    home.packages = [ tempScript ];

    programs.waybar.settings.${bar}."custom/cpu_temp" = {
      exec = "${tempScript}/bin/cpu_temp";
      return-type = "json";
      interval = 8;
      tooltip = true;
      on-click = "ghostty -e btop";
    };
  };
}
