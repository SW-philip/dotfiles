{ lib, ... }:
{
  options.myConfig.isDesktop = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether this is the desktop (dual monitor) profile.";
  };

  options.waybar.barName = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Override the waybar bar name for all modules. Empty = use per-module defaults.";
  };
}
