{ config, pkgs, lib, ... }:
let
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";

  ppScript = pkgs.writeShellScriptBin "waybar-powerprofile" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/powerprofile.sh "$@"
  '';
in {
  options.waybar.powerprofile.enable = lib.mkEnableOption "powerprofile module";

  config = lib.mkIf config.waybar.powerprofile.enable {
    home.packages = [ ppScript ];

    # ADDED THE UNDERSCORE HERE TO MATCH YOUR LOGS
    programs.waybar.settings.${bar}."custom/power_profile" = {
      exec = "${ppScript}/bin/waybar-powerprofile";
      "return-type" = "json";
      "restart-interval" = 30;
      "on-click" = "${ppScript}/bin/waybar-powerprofile toggle && pkill -RTMIN+1 waybar";
      signal = 1;
    };
  };
}
