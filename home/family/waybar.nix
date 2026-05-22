{ config, pkgs, lib, ... }:
let
  # TV-scaled palette: bump font size for 55" couch viewing at scale 2.0
  p = (import ../../themes/Rose-Pine/main/palette-main.nix) // {
    FONT_SIZE_BAR = "16px";
    BORDER_ACCENT_RGB = "235, 111, 146";
    SHADOW_RGB = "25, 23, 36";
    SHADOW_A_DROP = "0.4";
  };

  l = {
    gap = 10;
    borderW = 2;
    radiusSm = 4;
    radiusMd = 8;
    radiusLg = 12;
    shadowBlur = 12;
    shadowSpread = 2;
  };

  themesRoot = ../../themes;

  setTheme = pkgs.writeShellScriptBin "set-theme" ''
    THEME="''${1:-}"
    THEMES_ROOT="${themesRoot}"
    STATE="$HOME/.local/state"

    AVAILABLE=$(find "$THEMES_ROOT" -mindepth 3 -maxdepth 3 -name "palette-*.sh" \
      -exec basename {} .sh \; 2>/dev/null | sed 's/^palette-//' | sort)

    if [ -z "$THEME" ]; then
      echo "Usage: set-theme <theme>"
      echo "Available themes:"
      echo "$AVAILABLE" | while read -r slug; do echo "  - $slug"; done
      exit 0
    fi

    PALETTE_SH=$(find "$THEMES_ROOT" -mindepth 3 -maxdepth 3 -name "palette-$THEME.sh" 2>/dev/null | head -n1)
    if [ -z "$PALETTE_SH" ]; then
      echo "Error: Theme '$THEME' not found in $THEMES_ROOT"
      exit 1
    fi

    mkdir -p "$STATE"
    echo "$THEME" > "$STATE/theme"

    mkdir -p "$HOME/.config/waybar"
    cp "$PALETTE_SH" "$HOME/.config/waybar/palette.sh"

    pkill -SIGUSR2 waybar 2>/dev/null || true
    echo "Theme set to: $THEME"
  '';
in
{
  imports = [
    ../../modules/home-options.nix
    ../waybar/clock.nix
    ../waybar/bluetooth.nix
    ../waybar/netstatus.nix
    ../waybar/volume.nix
    ../waybar/weather.nix
    ../waybar/eggclock.nix
  ];

  waybar.barName = "mainBar";

  waybar.clock.enable     = true;
  waybar.bluetooth.enable = true;
  waybar.netstatus.enable = true;
  waybar.volume.enable    = true;
  waybar.weather.enable   = true;
  waybar.eggclock.enable  = true;

  home.packages = [ setTheme ];

  programs.waybar = {
    enable = true;
    systemd = {
      enable = true;
      target = "graphical-session.target";
    };
    settings.mainBar = {
      name      = "main-bar";
      layer     = "top";
      position  = "top";
      exclusive = true;
      height    = 64;

      modules-left = [
        "custom/start"
        "custom/eggclock"
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

  xdg.configFile."waybar/snark.json".source = ../waybar/snark.json;
  xdg.configFile."waybar/scripts" = {
    source    = ../waybar/scripts;
    recursive = true;
  };

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

  home.activation.waybarAssets = lib.hm.dag.entryAfter ["writeBoundary"] (
    let
      css = pkgs.writeText "waybar-style-family.css" (import ../waybar/style.nix { inherit p l; });
      mainPalette        = ../../themes/Rose-Pine/main/palette-main.sh;
      moonPalette        = ../../themes/Rose-Pine/moon/palette-moon.sh;
      dawnPalette        = ../../themes/Rose-Pine/dawn/palette-dawn.sh;
      lilacJuniperPalette = ../../themes/Rose-Pine/lilacJuniper/palette-lilacJuniper.sh;
    in
    ''
      THEME=$(cat "$HOME/.local/state/theme" 2>/dev/null || echo "main")
      mkdir -p "$HOME/.config/waybar"

      cp --remove-destination "${css}" "$HOME/.config/waybar/style.css"

      case "$THEME" in
        moon)            PALETTE_SH="${moonPalette}" ;;
        dawn|light)      PALETTE_SH="${dawnPalette}" ;;
        lilac-juniper)   PALETTE_SH="${lilacJuniperPalette}" ;;
        *)               PALETTE_SH="${mainPalette}" ;;
      esac
      cp --remove-destination "$PALETTE_SH" "$HOME/.config/waybar/palette.sh"
    ''
  );
}
