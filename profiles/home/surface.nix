# profiles/home/surface.nix
# Surface-specific home config. Imports base, adds tablet/touch/rotation things.
{ inputs, pkgs, lib, config, ... }:
{
  imports = [
    ./base.nix
    inputs.ignis.homeManagerModules.default
  ];

  programs.ignis = {
    enable = true;
    services.audio.enable   = true;
    services.network.enable  = true;
    services.bluetooth.enable = true;
  };

  ########################################
  # Surface HiDPI cursor override (base sets 48px; Surface needs 32px at 1.5x scale)
  ########################################
  home.pointerCursor.size = lib.mkForce 32;

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

  ########################################
  # Surface-only packages
  ########################################
  home.packages = with pkgs; [
    pandora
    wvkbd           # virtual keyboard
    xournalpp       # stylus note-taking
    foliate         # ebook reader
    koreader        # ebook reader (alternative)
  ];
}
