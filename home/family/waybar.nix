# home/family/waybar.nix
# Waybar for the family (Dell Latitude) niri session.
# Imports only the modules actually used — not the full waybar/default.nix.
{ config, pkgs, lib, ... }:
let
  # TV-scaled palette: bump font size for 55" couch viewing at scale 2.0
  p = (import ../../themes/Rose-Pine/main/palette-main.nix) // { FONT_SIZE_BAR = "16px"; };
in
{
  imports = [
    ../../modules/home-options.nix
    ../waybar/clock.nix
    ../waybar/bluetooth.nix
    ../waybar/netstatus.nix
    ../waybar/volume.nix
    ../waybar/weather.nix
  ];

  waybar.clock.enable = true;
  waybar.bluetooth.enable    = true;
  waybar.netstatus.enable    = true;
  waybar.volume.enable       = true;
  waybar.weather.enable      = true;

  programs.waybar = {
    enable = true;
    systemd = {
      enable = true;
      target = "graphical-session.targets";
    };
    settings.mainBar = {
      name      = "main-bar";
      layer     = "top";
      position  = "top";
      exclusive = false;
      height    = 64;

      modules-left = [
        "custom/start"
      ];
      modules-center = [
        "custom/clock"
        "custom/weather"
      ];
      modules-right = [
        "custom/volume"
        "custom/network"
        "custom/bluetooth"
        "tray"
      ];

      "custom/start" = {
        exec        = "echo '{\"text\": \"󱄅  Apps\", \"tooltip\": \"Applications\"}'";
        on-click    = "fuzzel";
        return-type = "json";
        interval    = "once";
      };
    };
  };

  # Shared assets from the main waybar config
  xdg.configFile."theme/palette.sh".source  = ../../themes/Rose-Pine/main/palette-main.nix;
  xdg.configFile."waybar/snark.json".source = ../waybar/snark.json;
  xdg.configFile."waybar/scripts" = {
    source    = ../waybar/scripts;
    recursive = true;
  };

  # Pre-seed weather location (Norristown home) — only written once, not overwritten
  home.activation.weatherLocation = lib.hm.dag.entryAfter ["writeBoundary"] ''
    LOC="$HOME/.config/waybar/weather_location.json"
    if [ ! -f "$LOC" ]; then
      mkdir -p "$(dirname "$LOC")"
      cat > "$LOC" <<'EOF'
{
  "USE_LOCATION": "home",
  "SAVED_LOCATIONS": [
    { "name": "home", "lat": 40.1215, "lon": -75.3399 }
  ]
}
EOF
    fi
  '';

  # Waybar CSS — write dark theme on activation
  home.activation.waybarStyleCss = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Provide both p and l to style.nix
    CSS="${pkgs.writeText "waybar-style-dark.css" (import ../waybar/style.nix {
      inherit p;
      l = { gap = 10; borderW = 2; }; # Add the layout settings style.nix wants
    })}"
    mkdir -p "$HOME/.config/waybar"
    cp --remove-destination "$CSS" "$HOME/.config/waybar/style.css"

    # Rest of your activation script...
    mkdir -p "$HOME/.config/waybar"
  '';

  # Restrict waybar to niri sessions only
  xdg.configFile."systemd/user/waybar.service.d/session-guard.conf".text = ''
    [Unit]
    ConditionEnvironment=XDG_SESSION_DESKTOP=niri
  '';
}
