# profiles/desktop.nix
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
        # Boost JBL to always win over built-in audio.
        # Any other BT sink gets second priority (fallback when JBL is off).
        "99-bt-priority" = {
          "monitor.bluez.rules" = [
            {
              matches = [{ "api.bluez5.address" = "YOUR-BT-HEADSET-MAC"; }];
              actions.update-props = {
                "priority.session" = 3000;
                "priority.driver"  = 3000;
              };
            }
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
  # RGB & Hardware Control (desktop only — Surface has no RGB)
  ############################################################
  services.hardware.openrgb.enable = true;
  services.hardware.openrgb.motherboard = "intel";
  hardware.i2c.enable = true;
  boot.kernelModules = [ "i2c-dev" "i2c-i801" ];
  boot.kernelParams = [ "acpi_enforce_resources=lax" ];

}
