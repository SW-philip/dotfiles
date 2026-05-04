# profiles/secure-boot.nix
# Lanzaboote Secure Boot for physical hosts with TPM2.
# Import alongside profiles/base.nix on desktop and surface.
{ ... }:
{
  # Limit signed UKIs on the ESP — lanzaboote honours this cap
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
}
