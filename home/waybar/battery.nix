{ config, pkgs, lib, ... }:

let
  isDesktop = config.myConfig.isDesktop;
  # Placed in the center of the surface bottom bar
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";

  batteryScript = pkgs.writeShellScriptBin "battery" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/battery.sh "$@"
  '';
in
{
  options.waybar.battery.enable = lib.mkEnableOption "battery module";

  config = lib.mkIf config.waybar.battery.enable {
    home.packages = [ batteryScript ];

    programs.waybar.settings.${bar}."custom/battery" = {
      exec = "${batteryScript}/bin/battery";
      return-type = "json";
      interval = 30;

      # Important: We just use {} here.
      # The script now provides the Glyph, the stacked stats, and the Pango markup.
      format = "{}";

      tooltip = true;
      # This is now handled entirely by the jq output in your battery.sh
      tooltip-format = "{}";

      # Since we removed wleave, keeping this empty or pointing it to a
      # power manager (like 'tlp-stat' in a terminal) is a good move.
      on-click = "";
    };
  };
}
