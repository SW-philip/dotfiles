{ ... }:
{
  # Config file is deployed via home.activation in home/niri/default.nix
  # (same pattern as ironbar style.css) so that toggle-theme can overwrite
  # it at runtime without blocking future nixos-rebuild activations.
  services.mako.enable = true;
}
