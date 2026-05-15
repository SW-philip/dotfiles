{ config, pkgs, lib, ... }:
let
  isDesktop = config.myConfig.isDesktop;
  bar = if config.waybar.barName != "" then config.waybar.barName
        else if isDesktop then "rightBar" else "surfaceBottomBar";

  bluetoothScript = pkgs.writeShellScriptBin "quantum-bluetooth" ''
    export PATH=${lib.makeBinPath [ pkgs.bluez pkgs.glib pkgs.jq ]}:$PATH
    exec ${config.home.homeDirectory}/.config/waybar/scripts/quantum-bluetooth.sh
  '';

  btmenuScript = pkgs.writeShellScriptBin "quantum-btmenu" ''
    export PATH=${lib.makeBinPath [
      pkgs.bemenu pkgs.bluez pkgs.glib pkgs.jq pkgs.libnotify pkgs.wireplumber pkgs.coreutils pkgs.gnused pkgs.gawk
    ]}:$PATH

    export BEMENU_BACKEND=wayland
    export WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-wayland-0}
    export XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

    exec ${config.home.homeDirectory}/.config/waybar/scripts/quantum-btmenu.sh
  '';

  bttoggleScript = pkgs.writeShellScriptBin "quantum-bt-toggle" ''
    export PATH=${lib.makeBinPath [ pkgs.bluez pkgs.glib ]}:$PATH
    exec ${config.home.homeDirectory}/.config/waybar/scripts/quantum-bt-toggle.sh
  '';
in {
  options.waybar.bluetooth.enable = lib.mkEnableOption "bluetooth module";

  config = lib.mkIf config.waybar.bluetooth.enable {
    home.packages = [ bluetoothScript btmenuScript bttoggleScript ];

    programs.waybar.settings.${bar}."custom/bluetooth" = {
      "exec" = "${bluetoothScript}/bin/quantum-bluetooth";
      "interval" = 1;
      "return-type" = "json";

      "on-click" = "${btmenuScript}/bin/quantum-btmenu";
      "on-click-right" = "${bttoggleScript}/bin/quantum-bt-toggle";

      "tooltip" = true;
    };
  };
}
