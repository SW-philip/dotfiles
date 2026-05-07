# ~/nixos/modules/protonvpn.nix
{ config, lib, pkgs, ... }:
{
  options.protonvpn.configFile = lib.mkOption {
    type = lib.types.path;
    description = "Path to the wg-quick .conf file for ProtonVPN";
  };

  config = {
    networking.wg-quick.interfaces.protonvpn = {
      configFile = config.protonvpn.configFile;
      # This ensures the service doesn't start automatically on boot if you don't want it to
      autostart = false;
    };

    networking.networkmanager.unmanaged = [ "protonvpn" ];
    networking.firewall.trustedInterfaces = [ "protonvpn" ];

    security.sudo.extraRules = [
      {
        users = [ "prepko" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/systemctl start wg-quick-protonvpn.service";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/systemctl stop wg-quick-protonvpn.service";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
