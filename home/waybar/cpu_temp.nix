{ config, pkgs, lib, ... }:

let
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";

  # --- THIS IS THE DEFINITION ---
  tempScript = pkgs.writeShellScriptBin "cpu_temp" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/cpu_temp.sh "$@"
  '';
  # ------------------------------

in # <--- This "in" makes the variables above available below
{
  options.waybar.cpu_temp.enable = lib.mkEnableOption "CPU Temperature module";

  config = lib.mkIf config.waybar.cpu_temp.enable {
    home.packages = [ tempScript ];

    programs.waybar.settings.${bar}."custom/cpu_temp" = {
      # Now Nix knows what 'tempScript' is
      exec = "${tempScript}/bin/cpu_temp";
      return-type = "json";
      interval = 8;
      tooltip = true;
      on-click = "ghostty -e btop";
    };
  };
}
