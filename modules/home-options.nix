{ lib, ... }:
{
  options.myConfig.isDesktop = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether this is the desktop (dual monitor) profile.";
  };
}
