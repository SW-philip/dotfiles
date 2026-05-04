{ config, pkgs, lib, ... }:

let
  scriptsDir = "${config.home.homeDirectory}/.config/waybar/scripts";
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";

  btrfsScript = pkgs.writeShellScriptBin "waybar-btrfs" ''
    export PATH="${pkgs.lib.makeBinPath [
      pkgs.jq
      pkgs.coreutils
      pkgs.btrfs-progs
      pkgs.util-linux
    ]}:$PATH"
    exec ${pkgs.bash}/bin/bash "${scriptsDir}/btrfs.sh" "$@"
  '';
in
{
  options.waybar.btrfs.enable = lib.mkEnableOption "btrfs health module";

  config = lib.mkIf config.waybar.btrfs.enable {
    home.packages = [ btrfsScript ];

    programs.waybar.settings.${bar}."custom/btrfs" = {
      exec        = "${btrfsScript}/bin/waybar-btrfs";
      return-type = "json";
      interval    = 60;
    };
  };
}
