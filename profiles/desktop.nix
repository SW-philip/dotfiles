{ config, pkgs, lib, ... }:
{
  ############################################################
  # Audio stack (PipeWire)
  ############################################################
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    jack.enable = true;
    wireplumber = {
      enable = true;
      extraConfig = {

        "99-bt-priority" = {
          "monitor.bluez.rules" = [
            {
              matches = [{ "node.name" = "~bluez_output.*"; }];
              actions.update-props = {
                "priority.session" = 2000;
                "priority.driver"  = 2000;
              };
            }
          ];
        };
      };
    };
  };

  ############################################################
  # Bluetooth
  ############################################################
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  hardware.enableAllFirmware = true;

  ############################################################
  # Power & policy
  ############################################################
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
  security.polkit.enable = true;

  ############################################################
  # i2c — required for RGB and hardware sensor access
  ############################################################
  hardware.i2c.enable = true;
  boot.kernelModules = [ "i2c-dev" "i2c-i801" ];
  boot.kernelParams = [ "acpi_enforce_resources=lax" ];

}
