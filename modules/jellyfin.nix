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

    environment = {
      # Without this, .NET defaults to 75% of system RAM for its GC heap
      DOTNET_GCHeapHardLimitPercent = "10";
    };

    serviceConfig = {
      ProtectHome = lib.mkForce false;
      ReadWritePaths = [ "/home/prepko/Videos" "/srv/Videos" ];
    };
  };
}
