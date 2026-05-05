{ config, pkgs, lib, ... }:

let
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";

  # Define the missing variable here
  idleScript = pkgs.writeShellScriptBin "waybar-idle-inhibit" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/idle-inhibit.sh "$@"
  '';
in
{
  options.waybar.idle_inhibit.enable = lib.mkEnableOption "idle_inhibit module";

  config = lib.mkIf config.waybar.idle_inhibit.enable {
    home.packages = [ idleScript ];

    programs.waybar.settings.${bar}."custom/idle_inhibit" = {
      # Use the store path for the main execution
      exec = "${idleScript}/bin/waybar-idle-inhibit";
      return-type = "json";
      interval = 5;

      # Use the store path for the toggle click as well
      on-click = "${idleScript}/bin/waybar-idle-inhibit toggle";
    };
  };
}
