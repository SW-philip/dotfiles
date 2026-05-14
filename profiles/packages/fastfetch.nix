{ pkgs, config, ... }:
let
  p = import ../../themes/Rose-Pine/moon/palette-moon.nix;

  # --- Helpers ---
  # ANSI Escape for TrueColor support
  esc = (builtins.fromTOML "x = \"\\u001B\"").x;
  toAnsi = color: let
    hex = builtins.substring 1 6 color;
    hexDigit = c: builtins.getAttr c {"0"=0;"1"=1;"2"=2;"3"=3;"4"=4;"5"=5;"6"=6;"7"=7;"8"=8;"9"=9;"a"=10;"b"=11;"c"=12;"d"=13;"e"=14;"f"=15;};
    hb = s: (hexDigit (builtins.substring 0 1 s) * 16) + hexDigit (builtins.substring 1 1 s);
    r = toString (hb (builtins.substring 0 2 hex));
    g = toString (hb (builtins.substring 2 2 hex));
    b = toString (hb (builtins.substring 4 2 hex));
  in "${esc}[38;2;${r};${g};${b}m";
  reset = "${esc}[0m";

  # Condensed Scripts
  scripts = {
    vpn = pkgs.writeShellScript "ff-vpn" ''
      iface=$(ip link show type wireguard 2>/dev/null | grep -oP '(?<=\d: )protonvpn-\S+(?=:)' | head -1)
      if [[ -n "$iface" ]]; then
        region=$(echo "''${iface#protonvpn-}" | tr '[:lower:]' '[:upper:]')
        echo "On ($region)"
      else
        echo "Off"
      fi
    '';

    lix = pkgs.writeShellScript "ff-lix" "nix --version 2>&1 | head -1 | awk '{print $NF}'";

    rebuild = pkgs.writeShellScript "ff-rebuild" ''
      elapsed=$(( $(date +%s) - $(stat -c %Y /run/current-system) ))
      days=$(( elapsed / 86400 ))
      (( days >= 14 )) && echo "''${days}d (stale)" || ((( days >= 7 )) && echo "''${days}d (aging)" || echo "''${days}d (fresh)")
    '';

    # Resolve artist + title from the active player (excluding sqlch db cache).
    # Streams report "Artist - Title" as a combined xesam:title with no xesam:artist —
    # detect and split on " - " as a fallback.
    npArtistTitle = pkgs.writeShellScript "ff-np-resolve" ''
      TITLE=$(playerctl --ignore-player=sqlch metadata xesam:title 2>/dev/null)
      ARTIST=$(playerctl --ignore-player=sqlch metadata xesam:artist 2>/dev/null)
      if [[ -z "$ARTIST" && "$TITLE" =~ " - " ]]; then
        ARTIST="''${TITLE%% - *}"
        TITLE="''${TITLE#* - }"
      fi
      echo "$ARTIST"
      echo "$TITLE"
    '';

    nowTitle = pkgs.writeShellScript "ff-np-title" ''
      mapfile -t NP < <(${scripts.npArtistTitle})
      echo "''${NP[1]}"
    '';

    nowArtist = pkgs.writeShellScript "ff-np-artist" ''
      mapfile -t NP < <(${scripts.npArtistTitle})
      echo "''${NP[0]}"
    '';

    enriched = pkgs.writeShellScript "ff-mpris-enriched" ''
      CACHE="$HOME/.cache/sqlch/enriched.json"
      [[ ! -f "$CACHE" ]] && exit 0
      mapfile -t NP < <(${scripts.npArtistTitle})
      KEY="''${NP[0],,}::''${NP[1],,}"
      jq -r --arg k "$KEY" '.[$k] | "\(.year // "") · \(.genres | join(", "))"' "$CACHE" | sed 's/^ · //;s/ · $//;s/null//g'
    '';

    album = pkgs.writeShellScript "ff-album" ''
      CACHE="$HOME/.cache/sqlch/enriched.json"
      mapfile -t NP < <(${scripts.npArtistTitle})
      KEY="''${NP[0],,}::''${NP[1],,}"
      ALBUM=$(jq -r --arg k "$KEY" '.[$k].album // empty' "$CACHE" 2>/dev/null)
      [[ -z "$ALBUM" ]] && ALBUM=$(playerctl --ignore-player=sqlch metadata xesam:album 2>/dev/null)
      echo "$ALBUM"
    '';
  };

  # Main Fetch Wrapper
  ff = pkgs.writeShellScriptBin "ff" ''
    ART_URL=$(playerctl --ignore-player=sqlch metadata mpris:artUrl 2>/dev/null)
    # Fallback: look up cover from enriched cache (covers streams that don't expose artUrl)
    if [[ -z "$ART_URL" || "$ART_URL" == "null" ]]; then
      mapfile -t NP < <(${scripts.npArtistTitle})
      KEY="''${NP[0],,}::''${NP[1],,}"
      ART_URL=$(jq -r --arg k "$KEY" '.[$k].cover // empty' "$HOME/.cache/sqlch/enriched.json" 2>/dev/null)
    fi
    if [[ -n "$ART_URL" && "$ART_URL" != "null" ]]; then
      ART_FILE="$HOME/.cache/sqlch/covers/$(echo "$ART_URL" | md5sum | cut -f1 -d' ').jpg"
      [[ ! -f "$ART_FILE" ]] && curl -fsSL "$ART_URL" -o "$ART_FILE"
      fastfetch --logo-source "$ART_FILE" --logo-type kitty --logo-height 20
    else
      fastfetch
    fi
  '';
in
{
  home.packages = [ ff ];
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = { source = "${config.home.homeDirectory}/.local/share/fastfetch/logo.png"; type = "kitty"; width = 22; height = 16; padding = { right = 4; top = 2; }; };
      display = { separator = "  "; key.width = 13; color.keys = p.IRIS; };
      modules = [
        { type = "title"; format = "╭───────────── {1}@{2} ─────────────╮"; color = { user = p.LOVE; host = p.IRIS; }; }
        { type = "custom"; format = "${toAnsi p.PINE}│ 󰄨  INTERIOR${reset}"; }
        { type = "host"; key = "󰋑  Host"; }
        { type = "cpu"; key = "󰻠  CPU"; }
        { type = "gpu"; key = "󰾲  GPU"; }
        { type = "os"; key = "󱄅  OS"; }
        { type = "command"; key = "🍦 Lix"; text = "${scripts.lix}"; }
        # --- Updated Kernel Glyph to Tux ---
        { type = "kernel"; key = "  Kernel"; }
        { type = "uptime"; key = "󰔛  Uptime"; }
        { type = "packages"; key = "󰏖  Packages"; }
        { type = "memory"; key = "󰍛  Memory"; percent.type = 3; }
        { type = "disk"; key = "󰋊  Disk (/)"; folders = "/"; percent.type = 3; }
      ] ++ (if config.myConfig.isDesktop then [
        { type = "disk"; key = "󱘲  srv"; folders = "/srv"; percent.type = 3; }
      ] else []) ++ [
        "break"
        { type = "custom"; format = "${toAnsi p.FOAM}│ 󰄨  EXTERIOR${reset}"; }
        { type = "wm"; key = "󰖲  WM"; }
        { type = "shell"; key = "󱆃  Shell"; }
        { type = "terminal"; key = "󰆿  Terminal"; }
        { type = "theme"; key = "󰏘  Theme"; }
        { type = "icons"; key = "󰀻  Icons"; }
        { type = "cursor"; key = "󰳾  Cursor"; }
        "break"
        { type = "custom"; format = "${toAnsi p.GOLD}│ 󰄨  SIGNAL${reset}"; }
        { type = "weather"; key = "󰖐  Weather"; location = "Philadelphia"; }
        { type = "command"; key = "󰖂  vpn"; text = "${scripts.vpn}"; }
        # --- Updated Rebuild Glyph to Hard Hat ---
        { type = "command"; key = "󱁤 rebuild"; text = "${scripts.rebuild}"; }
        "break"
        { type = "custom"; format = "${toAnsi p.ROSE}│ 󰄨  NOW PLAYING${reset}"; }
        { type = "command"; key = "󰎈  title"; text = "${scripts.nowTitle}"; }
        { type = "command"; key = "󰠃  artist"; text = "${scripts.nowArtist}"; }
        { type = "command"; key = "󰀾  album"; text = "${scripts.album}"; }
        { type = "command"; key = "    info"; text = "${scripts.enriched}"; }
        "break"
        { type = "custom"; format = "${toAnsi p.IRIS}╰──────────────────────────────────────╯${reset}"; }
        { type = "custom"; format = "  ${toAnsi p.LOVE}▄▄${toAnsi p.ROSE}▄▄${toAnsi p.GOLD}▄▄${toAnsi p.PINE}▄▄${toAnsi p.FOAM}▄▄${toAnsi p.IRIS}▄▄${reset}"; }
      ];
    };
  };
}
