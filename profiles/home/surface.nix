# profiles/home/surface.nix
# Surface-specific home config. Imports base, adds tablet/touch/rotation things.
{ inputs, pkgs, lib, config, ... }:
# let
#   iio-hyprland = inputs.iio-hyprland.packages.${pkgs.stdenv.hostPlatform.system}.default;
# in
{
  imports = [
    ./base.nix
  ];

  ########################################
  # Surface HiDPI cursor override (base sets 24px; Surface needs 32px at 1.5x scale)
  ########################################
  gtk.cursorTheme.size = lib.mkForce 32;

  ########################################
  # GNOME session — dark mode + cursor
  ########################################
  dconf.settings = {
    "org/gnome/desktop/interface" = lib.mkForce {
      color-scheme = "prefer-dark";
      cursor-theme = "BreezeX-RosePine-Linux";
      gtk-theme = "Adwaita-dark";
    };
  };

  # ########################################
  # # Surface-only systemd user services
  # ########################################
  # systemd.user.services.iio-hyprland = {
  #   Unit = {
  #     Description = "iio-hyprland auto-rotation daemon";
  #     After = [ "graphical-session.target" ];
  #     PartOf = [ "graphical-session.target" ];
  #     ConditionEnvironment = "XDG_SESSION_DESKTOP=Hyprland";
  #   };
  #   Install.WantedBy = [ "graphical-session.target" ];
  #   Service = {
  #     ExecStart = "${iio-hyprland}/bin/iio-hyprland";
  #     Restart = "on-failure";
  #   };
  # };

  ########################################
  # Surface-only packages
  ########################################
  home.packages = with pkgs; [
    pandora
    wvkbd           # virtual keyboard
    xournalpp       # stylus note-taking
    foliate         # ebook reader
    koreader        # ebook reader (alternative)
    # iio-hyprland
  ];

  # ########################################
  # # Surface HiDPI cursor overrides (hyprland)
  # ########################################
  # wayland.windowManager.hyprland.extraConfig = ''
  #   env = HYPRCURSOR_SIZE,32
  #   env = XCURSOR_SIZE,32
  # '';
}
