# ~/nixos/modules/protonvpn.nix
{ config, lib, ... }:
let
  cfg = config.protonvpn;
  names = lib.attrNames cfg.configs;
in
{
  options.protonvpn.configs = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = {};
    description = "Attrset of interface name → wg-quick .conf file path";
    example = lib.literalExpression ''
      {
        protonvpn    = config.sops.secrets.protonvpn_conf.path;
        protonvpn-ca = config.sops.secrets.protonvpn_ca_conf.path;
      }
    '';
  };

  config = lib.mkIf (names != []) {
    networking.wg-quick.interfaces = lib.mapAttrs (_: confFile: {
      configFile = confFile;
      autostart = false;
    }) cfg.configs;

    networking.networkmanager.unmanaged = names;
    networking.firewall.trustedInterfaces = names;

    security.sudo.extraRules = [{
      users = [ "prepko" ];
      commands = lib.concatMap (name: [
        {
          command = "/run/current-system/sw/bin/systemctl start wg-quick-${name}.service";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl stop wg-quick-${name}.service";
          options = [ "NOPASSWD" ];
        }
      ]) names;
    }];
  };
}
