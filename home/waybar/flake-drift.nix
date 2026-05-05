{ config, pkgs, lib, ... }:

let
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";

  driftScript = pkgs.writeShellScriptBin "waybar-flake-drift" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/flake-drift.sh "$@"
  '';
in
{
  options.waybar.flake-drift.enable = lib.mkEnableOption "flake-drift module";

  config = lib.mkIf config.waybar.flake-drift.enable {
    home.packages = [ driftScript ];

    programs.waybar.settings.${bar}."custom/flake-drift" = {
      exec = "${driftScript}/bin/waybar-flake-drift";
      return-type = "json";
      interval = 3600; # Check once an hour
      on-click = "${driftScript}/bin/waybar-flake-drift check";
    };
  };
}
