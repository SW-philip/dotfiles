{ config, pkgs, lib, ... }:

let
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";

  idleScript = pkgs.writeShellScriptBin "waybar-idle-inhibit" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/idle-inhibit.sh "$@"
  '';
in
{
  options.waybar.idle_inhibit.enable = lib.mkEnableOption "idle_inhibit module";

  config = lib.mkIf config.waybar.idle_inhibit.enable {
    home.packages = [ idleScript ];

    programs.waybar.settings.${bar}."custom/idle_inhibit" = {
      exec = "${idleScript}/bin/waybar-idle-inhibit";
      return-type = "json";
      interval = 5;
      on-click = "${idleScript}/bin/waybar-idle-inhibit toggle";
    };
  };
}
