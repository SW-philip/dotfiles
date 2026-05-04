{ config, pkgs, lib, ... }:
{
  ############################################################
  # Force linux-surface kernel (hard invariant)
  ############################################################
  boot.kernelPackages = lib.mkForce (pkgs.callPackage ../../pkgs/linux-surface-6_19 { });
}
