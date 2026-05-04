{ config, pkgs, lib, ... }:
let
  cfg = config.waybar.wleave;
  isDesktop = config.myConfig.isDesktop;
  bar = if isDesktop then "leftBottomBar" else "surfaceBottomBar";
  p = import ../../themes/Rose-Pine/main/palette-main.nix;
in
{
  options.waybar.wleave = {
    enable = lib.mkEnableOption "wleave waybar module";
    label = lib.mkOption {
      type = lib.types.str;
      default = "󰐻";
      description = "Label shown in the waybar button";
    };
    tooltip = lib.mkOption {
      type = lib.types.str;
      default = "<span foreground='${p.MUTED}'>Lock · Logout · Suspend · Hibernate · Shutdown · Reboot</span>\n<span foreground='${p.MUTED}'>────────────────────</span>\n<span foreground='${p.LOVE}'>There is no undo for this.</span>";
      description = "Tooltip text on hover";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.wleave ];

    programs.waybar.settings.${bar} = {
      "custom/wleave" = {
        format = "${cfg.label}";
        tooltip-format = cfg.tooltip;
        on-click = "wleave";
      };
    };
  };
}
