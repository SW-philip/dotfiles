{ config, pkgs, lib, ... }:
let
  isDesktop = config.myConfig.isDesktop;
  bar = if config.waybar.barName != "" then config.waybar.barName
        else if isDesktop then "rightBar" else "surfaceTopBar";

  volScript = pkgs.writeShellScriptBin "volume" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/volume.sh "$@"
  '';
in {
  options.waybar.volume.enable = lib.mkEnableOption "volume module";

  config = lib.mkIf config.waybar.volume.enable {
    home.packages = [ volScript ];

    programs.waybar.settings.${bar}."custom/volume" = {
      exec = "${volScript}/bin/volume";
      return-type = "json";
      signal = 1;
      on-click = "${volScript}/bin/volume toggle";
      on-click-right = "${config.home.homeDirectory}/.config/waybar/scripts/volume-popup.sh";
      on-click-middle = "${pkgs.pavucontrol}/bin/pavucontrol";
    };
  };
}
