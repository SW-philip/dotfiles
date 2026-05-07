# home/family/waybar.nix
# Waybar for the family (Dell Latitude) niri session.
# Imports only the modules actually used — not the full waybar/default.nix.
{ config, pkgs, lib, ... }:
let
  # TV-scaled palette: bump font size for 55" couch viewing at scale 2.0
  # Updated palette at the top of waybar.nix
  p = (import ../../themes/Rose-Pine/main/palette-main.nix) // {
    FONT_SIZE_BAR = "16px";
    # Ensure these exist if style.nix needs them
    BORDER_ACCENT_RGB = "235, 111, 146";
    SHADOW_RGB = "25, 23, 36";
    SHADOW_A_DROP = "0.4";
  };
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
  home.activation.waybarStyleCss = lib.hm.dag.entryAfter ["writeBoundary"] (
  let
    # Comprehensive layout set to satisfy all template requirements
    l = {
      gap = 10;
      borderW = 2;
      radiusSm = 4;
      radiusMd = 8;
      radiusLg = 12;    # Fixed: added missing radiusLg
      shadowBlur = 12;
      shadowSpread = 2;
    };
  in
  ''
    # Pass both p and the completed l set
    CSS="${pkgs.writeText "waybar-style-dark.css" (import ../waybar/style.nix {
      inherit p l;
    })}"

    mkdir -p "$HOME/.config/waybar"
    cp --remove-destination "$CSS" "$HOME/.config/waybar/style.css"
  '');
}
