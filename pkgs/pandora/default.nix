{ lib, rustPlatform, fetchFromGitHub, pkg-config, wayland, libxkbcommon }:

rustPlatform.buildRustPackage {
  pname = "pandora";
  version = "1.0.1";

  src = fetchFromGitHub {
    owner = "PandorasFox";
    repo  = "pandora";
    rev   = "e229675727aedc8917f1fe4f26895b5342546d50";
    hash  = "sha256-wuD8SR33bNC82iNujLztNHnwPZMGycp3aW8JDcypU2Y=";
  };

  cargoHash = "sha256-+EapLZMTZyAKX0cs24EOwaRJwq8J99H78qHYyVXuLD8=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ wayland libxkbcommon ];

  meta = with lib; {
    description = "Parallax-scrolling wallpaper daemon for Wayland/Niri";
    homepage    = "https://github.com/PandorasFox/pandora";
    license     = licenses.mit;
    platforms   = platforms.linux;
    mainProgram = "pandora";
  };
}
