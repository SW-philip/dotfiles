# profiles/niri.nix
# Niri compositor (system-level) — mirrors profiles/hyprland.nix
{ pkgs, ... }:
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
  environment.systemPackages = [ pkgs.xwayland-satellite ];

  ############################################################
  # XDG portal — gnome portal handles niri sessions
  # (programs.niri.enable registers the niri-portals.conf;
  #  we ensure xdg-desktop-portal-gnome is present as backend)
  ############################################################
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
  };

  ############################################################
  # Gnome Keyring — service + PAM integration for niri sessions
  ############################################################
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.niri.enableGnomeKeyring = true;
  # hyprlock authenticates under its own PAM service name — without this
  # entry, gnome-keyring stays locked after screen unlock in niri sessions
  security.pam.services.hyprlock.enableGnomeKeyring = true;

}
