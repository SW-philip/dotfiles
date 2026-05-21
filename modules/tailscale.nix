{ config, lib, ... }:
{
  services.tailscale.enable = true;
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };

  security.sudo.extraRules = [{
    users = [ config.myConfig.user ];
    commands = [
      {
        command = "/run/current-system/sw/bin/systemctl start tailscaled.service";
        options = [ "NOPASSWD" ];
      }
      {
        command = "/run/current-system/sw/bin/systemctl stop tailscaled.service";
        options = [ "NOPASSWD" ];
      }
    ];
  }];
}
