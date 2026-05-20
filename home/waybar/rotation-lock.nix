{ config, pkgs, lib, ... }:

let
  rotationScript = pkgs.writeShellScriptBin "waybar-rotation-lock" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/rotation-lock.sh "$@"
  '';
in
{
  options.waybar.rotation_lock.enable = lib.mkEnableOption "rotation_lock module";

  config = lib.mkIf config.waybar.rotation_lock.enable {
    home.packages = [ rotationScript ];

    programs.waybar.settings.surfaceBottomBar."custom/rotation_lock" =
      lib.mkIf (!config.myConfig.isDesktop) {
        exec = "${rotationScript}/bin/waybar-rotation-lock";
        return-type = "json";
        interval = 5;
        on-click = "${rotationScript}/bin/waybar-rotation-lock toggle";
      };
  };
}
