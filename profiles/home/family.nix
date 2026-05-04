# profiles/home/family.nix
# Home profile for the family user. Mirrors the pattern of desktop.nix / surface.nix.
# Host-specific overrides go here; shared config lives in home/family/default.nix.
{ ... }:
{
  imports = [ ../../home/family ];
}
