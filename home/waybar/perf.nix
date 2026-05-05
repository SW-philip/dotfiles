{ config, pkgs, lib, ... }:

let
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";

  perfScript = pkgs.writeShellScriptBin "waybar-perf" ''
    export PATH="${pkgs.lib.makeBinPath [
      pkgs.jq
      pkgs.coreutils
      pkgs.gawk
    ]}:$PATH"
    exec ${pkgs.bash}/bin/bash ${config.home.homeDirectory}/.config/waybar/scripts/perf.sh "$@"
  '';
in
{
  options.waybar.perf.enable = lib.mkEnableOption "CPU/memory performance module";

  config = lib.mkIf config.waybar.perf.enable {
    home.packages = [ perfScript ];

    programs.waybar.settings.${bar}."custom/perf" = {
      exec        = "${perfScript}/bin/waybar-perf";
      return-type = "json";
      interval    = 5;
      tooltip     = true;
      on-click    = "ghostty -e btop";
    };
  };
}
