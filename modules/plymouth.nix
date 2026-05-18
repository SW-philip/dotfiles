{ ... }:

{
  boot.consoleLogLevel = 0;

  boot.initrd.verbose = false;

  boot.plymouth = {
    enable = false;
    theme = "colorful";
    themePackages = [
      (pkgs.adi1090x-plymouth-themes.override {
        selected_themes = [ "colorful" ];
      })
    ];
  };
}
