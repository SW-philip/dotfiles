{ config, pkgs, lib, ... }:
let
  scriptsDir = "${config.home.homeDirectory}/.config/waybar/scripts";
  bar = config.waybar.barName;

  eggclockScript = pkgs.writeShellScriptBin "waybar-eggclock" ''
    exec ${pkgs.python3}/bin/python3 ${scriptsDir}/eggclock.py "$@"
  '';
in
{
  options.waybar.eggclock.enable = lib.mkEnableOption "Eggclock module";

  config = lib.mkIf config.waybar.eggclock.enable {
    home.packages = [ eggclockScript ];

    programs.waybar.settings.${bar}."custom/eggclock" = {
      exec = "${eggclockScript}/bin/waybar-eggclock";
      return-type = "json";
      interval = 60;
    };
  };
}
