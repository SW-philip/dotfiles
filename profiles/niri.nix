{ config, pkgs, ... }:
{
  ############################################################
  # Niri compositor (system-level)
  ############################################################
  programs.niri = {
    enable = true;
    package = pkgs.niri.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        substituteInPlace $out/bin/niri-session \
          --replace-fail \
            'systemctl --user import-environment' \
            'systemctl --user import-environment XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_CURRENT_DESKTOP DBUS_SESSION_BUS_ADDRESS'
      '';
    });
  };

  ############################################################
  # XWayland
  ############################################################
  programs.xwayland.enable = true;

  ############################################################
  # XDG portal
  ############################################################
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  ############################################################
  # GPU Screen Recorder
  ############################################################
  programs.gpu-screen-recorder.enable = true;
  environment.systemPackages = with pkgs; [
    xwayland-satellite
    config.programs.gpu-screen-recorder.package
    gpu-screen-recorder-gtk
  ];

  ############################################################
  # Gnome Keyring
  ############################################################
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.niri.enableGnomeKeyring = true;
  security.pam.services.hyprlock.enableGnomeKeyring = true;

}
