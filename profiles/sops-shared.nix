{ config, ... }: {
  sops.secrets.spotify_env = {
    sopsFile = ../secrets/shared.yaml;
    owner    = config.myConfig.user;
  };
  sops.secrets.openweathermap_api_key = {
    sopsFile = ../secrets/shared.yaml;
    owner    = config.myConfig.user;
  };
}
