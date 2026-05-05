{ pkgs, ... }:

{
  wrapScript = name: script: pkgs.writeShellScriptBin name ''
    export PATH="${pkgs.lib.makeBinPath [
      pkgs.jq
      pkgs.networkmanager
      pkgs.iproute2
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
      pkgs.bash
      pkgs.libnotify
      pkgs.wireplumber
      pkgs.pipewire
    ]}:$PATH"

    exec ${pkgs.bash}/bin/bash ${script} "$@"
  '';
}
