{ config, pkgs, lib, ... }:

{
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  users.users.jellyfin.extraGroups = [ "video" "render" "users" ];

  systemd.services.jellyfin = {
    after = lib.mkForce [ "network.target" ];
    wants = lib.mkForce [ "network.target" ];

    serviceConfig = {
      ProtectHome = lib.mkForce false;
      ReadWritePaths = [ "/home/prepko/Videos" "/srv/Videos" ];
    };
  };
}
