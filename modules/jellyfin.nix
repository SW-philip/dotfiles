{ config, pkgs, lib, ... }:

{
  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  users.users.jellyfin.extraGroups = [ "video" "render" "users" ];

  systemd.services.jellyfin = {
    after = lib.mkForce [ "network.target" ];
    wants = lib.mkForce [ "network.target" ];

    environment = {
      DOTNET_GCHeapHardLimitPercent = "10";
    };

    serviceConfig = {
      ProtectHome = lib.mkForce false;
      ReadWritePaths = [ "/home/${config.myConfig.user}/Videos" "/srv/Videos" ];
    };
  };
}
