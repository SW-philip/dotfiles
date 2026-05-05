{ config, pkgs, lib, ... }:

let
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";

  dndScript = pkgs.writeShellScriptBin "waybar-dnd" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/dnd-toggle.sh "$@"
  '';
in
{
  options.waybar.dnd.enable = lib.mkEnableOption "dnd module";

  config = lib.mkIf config.waybar.dnd.enable {
    home.packages = [ dndScript ];

    programs.waybar.settings.${bar}."custom/dnd" = {
      exec = "${dndScript}/bin/waybar-dnd";
      return-type = "json";
      interval = 30;
      on-click = "${dndScript}/bin/waybar-dnd toggle";
    };
  };
}
