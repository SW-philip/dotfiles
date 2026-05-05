# nixos/modules/sqlch.nix
{ config, pkgs, lib, ... }:

let
  sqlch = pkgs.sqlch;
in
{
  environment.systemPackages = [ sqlch ];
}
