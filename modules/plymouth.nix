{ pkgs, ... }:

{
  boot.consoleLogLevel = 0;

  boot.initrd = {
    verbose = false;
    systemd.packages = [ pkgs.plymouth ];
    systemd.services.plymouth.enable = true;
  };

  boot.plymouth = {
    enable = true;
    theme = "colorful";
    themePackages = [
      (pkgs.adi1090x-plymouth-themes.override {
        selected_themes = [ "colorful" ];
      })
    ];
  };
}
