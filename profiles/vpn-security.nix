{ ... }: {
  security.sudo.extraRules = [{
    users = [ "prepko" ];
    commands = [
      { command = "/run/current-system/sw/bin/systemctl start wg-quick-protonvpn.service"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/systemctl stop wg-quick-protonvpn.service"; options = [ "NOPASSWD" ]; }
    ];
  }];
}
