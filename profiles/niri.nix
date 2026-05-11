# profiles/niri.nix
# Niri compositor (system-level) — mirrors profiles/hyprland.nix
{ config, pkgs, ... }:
{
  ############################################################
  # Niri compositor (system-level)
  ############################################################
  programs.niri = {
    enable = true;
    # Patch niri-session: systemd 256+ deprecated bare `import-environment`
    # (no args). List only the variables the display manager has already set at
    # this point — BEFORE niri.service starts. WAYLAND_DISPLAY is not available
    # here; niri --session exports it to systemd itself once the socket is up.
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
  # XWayland — required for Steam and other X11 apps
  # xwayland-satellite bridges rootful XWayland for niri sessions.
  ############################################################
  programs.xwayland.enable = true;

  ############################################################
  # XDG portal — gtk backend for file chooser, access, notifications.
  # programs.niri.enable installs niri-portals.conf; user-level override
  # at ~/.config/xdg-desktop-portal/niri-portals.conf routes FileChooser
  # explicitly to gtk (gnome portal refuses dialogs outside a GNOME session).
  ############################################################
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  ############################################################
  # GPU Screen Recorder — cap_sys_admin wrapper for KMS capture
  # The module overrides the package with wrapperDir so the binary
  # finds gsr-kms-server in /run/wrappers/bin/ (capability-aware).
  ############################################################
  programs.gpu-screen-recorder.enable = true;
  environment.systemPackages = with pkgs; [
    xwayland-satellite
    config.programs.gpu-screen-recorder.package
    gpu-screen-recorder-gtk
  ];

  ############################################################
  # Gnome Keyring — service + PAM integration for niri sessions
  ############################################################
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.niri.enableGnomeKeyring = true;
  # hyprlock authenticates under its own PAM service name — without this
  # entry, gnome-keyring stays locked after screen unlock in niri sessions
  security.pam.services.hyprlock.enableGnomeKeyring = true;

}
