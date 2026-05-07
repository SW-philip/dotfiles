{ config, pkgs, lib, ... }:

let
  isDesktop = config.myConfig.isDesktop;
  # Keeping your previous logic for clock placement
  bar = if config.waybar.barName != "" then config.waybar.barName
        else if isDesktop then "leftBar" else "surfaceBottomBar";

  clockScript = pkgs.writeShellScriptBin "quantum-clock" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/quantum_clock.sh "$@"
  '';
in
{
  options.waybar.clock.enable = lib.mkEnableOption "clock module";

  config = lib.mkIf config.waybar.clock.enable {
    home.packages = [ clockScript ];

    programs.waybar.settings.${bar}."custom/clock" = {
      exec = "${clockScript}/bin/quantum-clock";
      return-type = "json";
      interval = 1;
      # Opens the calendar on click
      on-click       = "${clockScript}/bin/quantum-clock next";
      on-click-right = "${pkgs.gnome-calendar}/bin/gnome-calendar";
    };
  };
}
