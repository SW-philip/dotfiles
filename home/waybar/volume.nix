{ config, pkgs, lib, ... }:
let
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "rightBar" else "surfaceTopBar";

  # --- FIX: Define the missing variable here ---
  volScript = pkgs.writeShellScriptBin "volume" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/volume.sh "$@"
  '';
in {
  options.waybar.volume.enable = lib.mkEnableOption "volume module";

  config = lib.mkIf config.waybar.volume.enable {
    # It's good practice to add the script to your home packages too
    home.packages = [ volScript ];

    programs.waybar.settings.${bar}."custom/volume" = {
      exec = "${volScript}/bin/volume";
      return-type = "json";
      signal = 1;
      on-scroll-up = "${volScript}/bin/volume right";
      on-scroll-down = "${volScript}/bin/volume left";
      on-scroll-right = "${volScript}/bin/volume right";
      on-scroll-left = "${volScript}/bin/volume left";
      on-click = "${volScript}/bin/volume toggle";
      on-click-right = "${config.home.homeDirectory}/.config/waybar/scripts/volume-popup.sh";
      on-click-middle = "${pkgs.pavucontrol}/bin/pavucontrol";
    };
  };
}
