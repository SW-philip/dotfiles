{ config, pkgs, lib, ... }:
let
  scriptsDir = "${config.home.homeDirectory}/.config/waybar/scripts";
  isDesktop = config.myConfig.isDesktop;

  # Match surfaceBottomBar where it is listed in modules-center
  bar = if config.waybar.barName != "" then config.waybar.barName
        else if isDesktop then "leftBar" else "surfaceTopBar";

  python = pkgs.python3.withPackages (ps: with ps; [ requests ]);

  weatherScript = pkgs.writeShellScriptBin "waybar-weather" ''
    export PATH="${lib.makeBinPath [ python pkgs.bemenu pkgs.coreutils ]}:$PATH"
    if [ -f /run/secrets/openweathermap_api_key ]; then
      export OPENWEATHERMAP_API_KEY="$(cat /run/secrets/openweathermap_api_key)"
    elif [ -f "$HOME/.config/waybar/.weather_api_key" ]; then
      export OPENWEATHERMAP_API_KEY="$(cat "$HOME/.config/waybar/.weather_api_key")"
    fi
    exec ${python}/bin/python3 ${scriptsDir}/weather.py "$@"
  '';
in
{
  options.waybar.weather.enable = lib.mkEnableOption "Weather module";

  config = lib.mkIf config.waybar.weather.enable {
    home.packages = [ weatherScript pkgs.bemenu ];

    programs.waybar.settings.${bar}."custom/weather" = {
      exec = "${weatherScript}/bin/waybar-weather";
      on-click = "bash ${scriptsDir}/weather_toggle.sh";
      on-click-right = "env BUTTON=3 ${weatherScript}/bin/waybar-weather";
      return-type = "json";
      interval = 300;
      markup = true;
    };
  };
}
