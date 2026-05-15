{ config, pkgs, lib, ... }:
let
  isDesktop = config.myConfig.isDesktop;
  bar = if config.waybar.barName != "" then config.waybar.barName
        else if isDesktop then "rightBar" else "surfaceBottomBar";

  netstatusScript = pkgs.writeShellScriptBin "netstatus" ''
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/netstatus.sh "$@"
  '';
in {
  options.waybar.netstatus.enable = lib.mkEnableOption "netstatus module";
  config = lib.mkIf config.waybar.netstatus.enable {
    home.packages = [ netstatusScript ];
    programs.waybar.settings.${bar}."custom/network" = {
      exec = "${netstatusScript}/bin/netstatus"; # Use absolute path
      return-type = "json";
      interval = 5;
      tooltip = true;
      format = "{}";

      on-click = "bash ${config.home.homeDirectory}/.config/waybar/scripts/quantum-wifimenu.sh";
      on-click-right = "bash ${config.home.homeDirectory}/.config/waybar/scripts/vpn-toggle.sh";
    };
  };
}
