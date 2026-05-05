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
    };
    networking.networkmanager.unmanaged = [ "protonvpn" ];
    networking.firewall.trustedInterfaces = [ "protonvpn" ];

    security.sudo.extraRules = [
      {
        users = [ "prepko" ];
        commands = [
          {
            command = "${pkgs.systemd}/bin/systemctl start wg-quick-protonvpn.service";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${pkgs.systemd}/bin/systemctl stop wg-quick-protonvpn.service";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
