{ config, pkgs, lib, ... }:

let
  scriptsDir = "${config.home.homeDirectory}/.config/waybar/scripts";
  isDesktop   = config.myConfig.isDesktop;

  sleepDrainScript = pkgs.writeShellScriptBin "waybar-sleep-drain" ''
    export PATH="${pkgs.lib.makeBinPath [
      pkgs.jq
      pkgs.coreutils
      pkgs.procps
    ]}:$PATH"
    exec ${pkgs.bash}/bin/bash "${scriptsDir}/sleep-drain.sh" "$@"
  '';
in
{
  options.waybar.sleepDrain.enable = lib.mkEnableOption "Sleep drain tracker";

  config = lib.mkIf config.waybar.sleepDrain.enable {
    home.packages = [ sleepDrainScript ];

    programs.waybar.settings.surfaceBottomBar = lib.mkIf (!isDesktop) {
      "custom/sleep_drain" = {
        exec        = "${sleepDrainScript}/bin/waybar-sleep-drain";
        return-type = "json";
        interval    = 60;
        signal      = 2;
      };
    };
  };
}
