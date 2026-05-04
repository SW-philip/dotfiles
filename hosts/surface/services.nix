{pkgs, lib, ...}:
{
 services.smartd = {
   enable = true;
   autodetection = true;
   notifications.wall.enable = true; # Sends a terminal message on failure
 };
}
