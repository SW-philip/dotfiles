{ lib, python3, python3Packages, gtk4, gobject-introspection, wrapGAppsHook3 }:

python3Packages.buildPythonApplication {
  pname = "uniremote";
  version = "0.1.0";

  src = ./.;
  format = "other";

  propagatedBuildInputs = with python3Packages; [
    pygobject3
    requests
  ];

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
  ];

  buildInputs = [ gtk4 ];

  installPhase = ''
    mkdir -p $out/bin $out/${python3.sitePackages}
    cp uniremote_api.py $out/${python3.sitePackages}/uniremote_api.py
    install -m755 uniremote_gtk.py $out/bin/uniremote
  '';

  meta = with lib; {
    description = "GTK4 Roku/Samsung remote";
    platforms = platforms.linux;
  };
}
