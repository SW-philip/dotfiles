# profiles/sops-shared.nix
# Secrets common to desktop and surface (both use secrets/shared.yaml).
# Family declares openweathermap_api_key separately (different owner).
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
