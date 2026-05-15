{ config, pkgs, lib, ... }:
let
  cfg = config.waybar.uniremote;
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";
  p = import ../../themes/Rose-Pine/main/palette-main.nix;
in
{
  options.waybar.uniremote = {
    enable = lib.mkEnableOption "uniremote waybar launcher";
    label = lib.mkOption {
      type = lib.types.str;
      default = "󰑗";
    };
    tooltip = lib.mkOption {
      type = lib.types.str;
      default = "<span foreground='${p.MUTED}'>Remote Control</span>\n<span foreground='${p.MUTED}'>────────────────────</span>\n<span foreground='${p.IRIS}'>Commanding things from a distance since the invention of laziness.</span>";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.waybar.settings.${bar}."custom/uniremote" = {
      format = cfg.label;
      tooltip-format = cfg.tooltip;
      on-click = "uniremote";
    };
  };
}
