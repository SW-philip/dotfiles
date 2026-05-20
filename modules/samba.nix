{ config, ... }:
{
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = config.networking.hostName;
        "map to guest" = "never";
      };
      "media" = {
        "path" = "/srv/Videos";
        "browseable" = "yes";
        "valid users" = "prepko";
        "read only" = "yes";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
}
