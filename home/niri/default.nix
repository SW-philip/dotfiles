# home/niri/default.nix
# Niri home-manager config — cleanroom compositor for focused work
{ config, pkgs, lib, ... }:
let
  # ── Theme auto-discovery ─────────────────────────────────────────────────
  # Convention: themes/[Family]/[folderName]/
  #   palette-[camelCase].sh   — shell palette for zsh/fzf at runtime
  #   palette-[hyphenated].nix — Nix attrs for CSS/config generation at build time
  # Slug (theme state key) is derived from the .nix filename, not the folder name,
  # so folder naming is flexible (e.g. "original/" → slug "original-lix").
  # Light vs dark is inferred from FONT_SIZE_BAR ("13px" = light).
  # To add a theme: drop files in a new subfolder — no changes needed here.

  themesRoot = ../../themes;
  l          = import "${themesRoot}/layout.nix";

  # Returns { slug → { family, slug, palette, shContent, isLight } } for every
  # theme found under themes/[Family]/[folderName]/
  allThemes =
    let
      loadTheme = family: folderName:
        let
          dir   = "${themesRoot}/${family}/${folderName}";
          files = builtins.readDir dir;

          # Slug comes from the .nix filename: "palette-rocky-road.nix" → "rocky-road"
          nixName = builtins.head (builtins.attrNames (
            lib.filterAttrs (n: _: lib.hasPrefix "palette-" n && lib.hasSuffix ".nix" n) files));
          slug = lib.removeSuffix ".nix" (lib.removePrefix "palette-" nixName);

          shName = builtins.head (builtins.attrNames (
            lib.filterAttrs (n: _: lib.hasPrefix "palette-" n && lib.hasSuffix ".sh" n) files));

          wallpaperFiles = lib.filterAttrs (n: _:
            lib.hasPrefix "wallpaper-" n && lib.hasSuffix ".png" n
          ) files;

          # Explicitly find the png, don't just take the first result of an unsorted list
          wallpaper = if wallpaperFiles != {}
                      then "${dir}/${builtins.head (builtins.attrNames wallpaperFiles)}"
                      else null;

          p = import "${dir}/${nixName}";
        in {
          inherit family slug wallpaper dir;
          palette   = p;
          shContent = builtins.readFile "${dir}/${shName}";
          # isLight explicit wins; fall back to FONT_SIZE_BAR heuristic ("13px" = light)
          isLight   = p.isLight or ((p.FONT_SIZE_BAR or "12px") == "13px");
        };

      familyDirs = lib.filterAttrs (_: t: t == "directory") (builtins.readDir themesRoot);

      familyThemes = family:
        let themeDirs = lib.filterAttrs (_: t: t == "directory")
                          (builtins.readDir "${themesRoot}/${family}");
        in lib.mapAttrs' (folder: _:
             let t = loadTheme family folder;
             in lib.nameValuePair t.slug t
           ) themeDirs;

    in lib.foldlAttrs (acc: family: _: acc // familyThemes family) {} familyDirs;

  # ── Theme config templates ────────────────────────────────────────────────

  mkMakoConfig = p: subtleBorder: faintBorder: ''
    default-timeout=5000
    width=400
    margin=16
    padding=12
    border-size=1
    border-radius=${toString (l.radiusSm + 1)}
    sort=-time
    max-visible=5
    font=JetBrains Mono 11
    background-color=${p.SURFACE}ff
    text-color=${p.TEXT}ff
    border-color=${subtleBorder}
    progress-color=over ${p.TINT_PINE_DARK}ff

    [app-name=sqlch]
    default-timeout=8000
    border-size=2
    border-color=${p.FOAM}aa
    background-color=${p.TINT_PINE_MID}ff
    text-color=${p.FOAM}ff

    [urgency=low]
    background-color=${p.BASE}ff
    text-color=${p.SUBTLE}ff
    border-color=${faintBorder}
    default-timeout=3000

    [urgency=normal]
    background-color=${p.SURFACE}ff
    text-color=${p.TEXT}ff
    border-color=${subtleBorder}

    [urgency=critical]
    background-color=${p.TINT_CRITICAL_BG}ff
    text-color=${p.CRITICAL}ff
    border-color=${p.CRITICAL}59
    default-timeout=0

    [mode=do-not-disturb]
    invisible=1
  '';

  # ── Per-theme fastfetch logo (color-injected cone PNG) ───────────────────
  mkFastfetchLogo = t:
    let
      p            = t.palette;
      iceDefault   = p.BASE  or "#1a1830";
      iceMid       = p.LOVE  or (p.IRIS  or "#b55690");
      iceHighlight = p.FOAM  or (p.IRIS  or "#d162a4");
      hasOverrides = builtins.pathExists "${t.dir}/wallpaper-colors.sh";
    in pkgs.runCommand "fastfetch-logo-${t.slug}.png" {
      nativeBuildInputs = [ pkgs.librsvg ];
    } ''
      cp ${../../assets/just-the-cone-web.svg} cone.svg

      ICE_SHADOW="${iceDefault}"
      ICE_MID="${iceMid}"
      ICE_HIGHLIGHT="${iceHighlight}"
      CONE_SHADOW="#F38D30"
      CONE_MID="#F9A454"

      ${lib.optionalString hasOverrides "source ${t.dir}/wallpaper-colors.sh"}

      sed -i \
        "s|#a30262|''${ICE_SHADOW}|g; \
         s|#b55690|''${ICE_MID}|g; \
         s|#d162a4|''${ICE_HIGHLIGHT}|g; \
         s|#ef7627|''${CONE_SHADOW}|g; \
         s|#ff9a56|''${CONE_MID}|g" \
        cone.svg

      rsvg-convert -w 280 cone.svg -o $out
    '';

  # ── Per-theme derivations — generated from allThemes ─────────────────────
  themeConfigs = lib.mapAttrs (slug: t:
    let
      subtleBorder = if t.isLight then "#0000000a" else "#ffffff0a";
      faintBorder  = if t.isLight then "#00000006" else "#ffffff06";
      wallpaper    = if t.wallpaper != null then t.wallpaper
                     else if t.isLight then "${home}/Images/rothkos_dawn_tall.png"
                     else "${home}/Images/rothkos_moon_tall.png";
    in {
      mako       = pkgs.writeText "mako-config-${slug}"       (mkMakoConfig t.palette subtleBorder faintBorder);
      niriKdl    = pkgs.writeText "niri-config-${slug}.kdl"   (import ./config.kdl.nix { p = t.palette; inherit l; cursorSize = if config.myConfig.isDesktop then 24 else 48; });
      waybarCss  = pkgs.writeText "waybar-style-${slug}.css"  (import ../waybar/style.nix { p = t.palette; inherit l; });
      waybarSh   = pkgs.writeText "waybar-palette-${slug}.sh" t.shContent;
      nemoCss    = pkgs.writeText "nemo-gtk3-${slug}.css"     (import ../nemo/gtk3.css.nix t.palette);
      wofiCss    = pkgs.writeText "wofi-style-${slug}.css"    (mkWofiCss t.palette);
      fuzzelIni  = pkgs.writeText "fuzzel-${slug}.ini"        (mkFuzzelIni t.palette);
      wleaveCss     = pkgs.writeText "wleave-style-${slug}.css"  (mkWleaveCSS t.palette);
      cava          = pkgs.writeText "cava-config-${slug}"       (mkCavaConfig t.palette);
      ghostty       = pkgs.writeText "ghostty-config-${slug}"    (mkGhosttyConfig t.palette);
      pandora       = pkgs.writeText "pandora-${slug}.kdl"       (mkPandoraCfg wallpaper);
      wallpaperPath = wallpaper;
      fastfetchLogo = mkFastfetchLogo t;
    }
  ) allThemes;

  home = config.home.homeDirectory;

  # swaybg launcher — reads wallpaper path from state file so the
  # systemd service can be restarted with a new image without changing the unit.
  # Uses output '*' to cover all connected outputs (works for both single eDP-1
  # and dual DP-4/DP-3 setups).
  swaybgLauncher = pkgs.writeShellScript "swaybg-launcher" ''
    exec ${pkgs.swaybg}/bin/swaybg -o '*' -i "$(cat "$HOME/.local/state/wallpaper")" -m fill
  '';

  mkPandoraCfg = wallpaper:
    if config.myConfig.isDesktop then ''
      output "DP-3" {
          image "${wallpaper}"
          mode "scroll-vertical"
      }
      output "DP-4" {
          image "${wallpaper}"
          mode "scroll-vertical"
      }
      animation {}
    '' else ''
      output "eDP-1" {
          image "${wallpaper}"
          mode "static"
      }
      animation {}
    '';
  mkCavaConfig = p: ''
    [general]
    framerate = 60
    sensitivity = 100
    bars = 0
    bar_width = 2
    bar_spacing = 1
    sleep_timer = 0

    [output]
    method = ncurses
    channels = stereo
    orientation = bottom

    [smoothing]
    noise_reduction = 77

    [color]
    background = '${p.BASE}'
    gradient = 1
    gradient_count = 5
    gradient_color_1 = '${p.PINE}'
    gradient_color_2 = '${p.FOAM}'
    gradient_color_3 = '${p.IRIS}'
    gradient_color_4 = '${p.ROSE}'
    gradient_color_5 = '${p.LOVE}'
  '';

  mkGhosttyConfig = p: ''
    # Rosé Pine terminal palette — regenerated by toggle-theme
    # ANSI 0-7: base colors; 8-15: bright variants (identical in Rosé Pine)
    palette = 0=${p.OVERLAY}
    palette = 1=${p.LOVE}
    palette = 2=${p.PINE}
    palette = 3=${p.GOLD}
    palette = 4=${p.FOAM}
    palette = 5=${p.IRIS}
    palette = 6=${p.ROSE}
    palette = 7=${p.TEXT}
    palette = 8=${p.HIGHLIGHT_LOW}
    palette = 9=${p.LOVE}
    palette = 10=${p.PINE}
    palette = 11=${p.GOLD}
    palette = 12=${p.FOAM}
    palette = 13=${p.IRIS}
    palette = 14=${p.ROSE}
    palette = 15=${p.TEXT}

    background = ${p.BASE}
    foreground = ${p.TEXT}

    cursor-color = ${p.IRIS}
    cursor-text = ${p.BASE}

    selection-background = ${p.HIGHLIGHT_MED}
    selection-foreground = ${p.TEXT}

    font-family = JetBrainsMono Nerd Font
    font-family = Symbols Nerd Font Mono

    window-padding-x = 12
    window-padding-y = 8
  '';

  mkWofiCss = p: ''
    window {
      background-color: ${p.BASE};
      font-family: "JetBrainsMono Nerd Font";
      font-size: 12px;
    }

    #entry {
      margin: 5px;
      padding: 8px;
      border-radius: ${toString l.radiusSm}px;
      background-color: ${p.BASE};
      color: ${p.TEXT};
    }

    #entry:selected {
      background-color: ${p.OVERLAY};
      color: ${p.PINE};
    }

    #input {
      background-color: ${p.SURFACE};
      color: ${p.TEXT};
      border: 2px solid ${p.IRIS};
      padding: 6px;
      margin: 5px;
    }

    #text {
      color: ${p.TEXT};
    }

    #text:selected {
      color: ${p.PINE};
    }
  '';

  mkWleaveCSS = p: ''
    * {
        background-image: none;
        font-family: "JetBrainsMono Nerd Font", monospace;
        font-size: 36px;
    }

    window {
        background-color: ${p.BASE};
    }

    button {
        color: ${p.TEXT};
        background-color: ${p.SURFACE};
        border: 2px solid ${p.OVERLAY};
        border-radius: ${toString l.radiusLg}px;
        margin: 8px;
        outline-style: none;
        box-shadow: none;
        text-shadow: none;
        background-repeat: no-repeat;
        background-position: center 35%;
        background-size: 20%;
        transition: all 0.2s ease-in-out;
    }

    button:hover {
        background-color: ${p.OVERLAY};
        border-color: ${p.SUBTLE};
        color: ${p.TEXT};
        background-size: 23%;
        outline-style: none;
    }

    button:focus {
        background-color: ${p.OVERLAY};
        border-color: ${p.IRIS};
        outline-style: none;
    }

    #lock:hover      { border-color: ${p.FOAM}; color: ${p.FOAM}; }
    #logout:hover    { border-color: ${p.LOVE}; color: ${p.LOVE}; }
    #suspend:hover   { border-color: ${p.IRIS}; color: ${p.IRIS}; }
    #hibernate:hover { border-color: ${p.GOLD}; color: ${p.GOLD}; }
    #shutdown:hover  { border-color: ${p.LOVE}; color: ${p.LOVE}; }
    #reboot:hover    { border-color: ${p.ROSE}; color: ${p.ROSE}; }
  '';

  mkFuzzelIni = p:
    let c = hex: (lib.removePrefix "#" hex) + "ff";
    in ''
      [main]
      font=monospace:size=13
      dpi-aware=auto
      prompt=
      terminal=ghostty -e
      layer=overlay
      show-actions=yes
      width=35
      lines=8

      [colors]
      background=${c p.BASE}
      text=${c p.TEXT}
      match=${c p.IRIS}
      selection=${c p.OVERLAY}
      selection-text=${c p.ROSE}
      selection-match=${c p.FOAM}
      border=${c p.PINE}

      [border]
      width=1
      radius=${toString l.radiusSm}
    '';

  # Standalone runtime script — baked-in nix store paths for every theme.
  # Called by set-theme at runtime and by home.activation.applyTheme on nrs.
  applyThemeScript = pkgs.writeShellScriptBin "apply-theme" (
    ''
      THEME="''${1:-$(cat "$HOME/.local/state/theme" 2>/dev/null || echo "main")}"
      [ "$THEME" = "dark" ]  && THEME="main"
      [ "$THEME" = "light" ] && THEME="dawn"
      case "$THEME" in
    ''
    + lib.concatStrings (lib.mapAttrsToList (slug: cfgs: ''
        ${slug})
          MAKO_CFG="${cfgs.mako}"
          NIRI_CFG="${cfgs.niriKdl}"
          WAYBAR_CSS="${cfgs.waybarCss}"
          WAYBAR_PALETTE="${cfgs.waybarSh}"
          NEMO_CSS="${cfgs.nemoCss}"
          WOFI_CSS="${cfgs.wofiCss}"
          FUZZEL_INI="${cfgs.fuzzelIni}"
          PANDORA_CFG="${cfgs.pandora}"
          WALLPAPER_PATH="${cfgs.wallpaperPath}"
          WLEAVE_CSS="${cfgs.wleaveCss}"
          CAVA_CFG="${cfgs.cava}"
          GHOSTTY_CFG="${cfgs.ghostty}"
          FASTFETCH_LOGO="${cfgs.fastfetchLogo}"
          ;;
      '') themeConfigs)
    + ''
        *)
          echo "apply-theme: unknown theme ''${THEME}" >&2
          exit 1
          ;;
      esac
      mkdir -p "$HOME/.config/mako"
      cp "$MAKO_CFG" "$HOME/.config/mako/config"
      mkdir -p "$HOME/.config/niri"
      cp "$NIRI_CFG" "$HOME/.config/niri/config.kdl"
      mkdir -p "$HOME/.config/waybar"
      cp "$WAYBAR_CSS" "$HOME/.config/waybar/style.css"
      cp "$WAYBAR_PALETTE" "$HOME/.config/waybar/palette.sh"
      mkdir -p "$HOME/.config/gtk-3.0"
      cp --remove-destination "$NEMO_CSS" "$HOME/.config/gtk-3.0/gtk.css"
      mkdir -p "$HOME/.config/wofi"
      cp "$WOFI_CSS" "$HOME/.config/wofi/style.css"
      mkdir -p "$HOME/.config/fuzzel"
      cp "$FUZZEL_INI" "$HOME/.config/fuzzel/fuzzel.ini"
      mkdir -p "$HOME/.local/state"
      echo "$WALLPAPER_PATH" > "$HOME/.local/state/wallpaper"
      mkdir -p "$HOME/.config/cava"
      cp "$CAVA_CFG" "$HOME/.config/cava/config"
      mkdir -p "$HOME/.config/ghostty"
      cp "$GHOSTTY_CFG" "$HOME/.config/ghostty/config"
      mkdir -p "$HOME/.config/wleave"
      cp "$WLEAVE_CSS" "$HOME/.config/wleave/style.css"
      mkdir -p "$HOME/.local/share/fastfetch"
      ln -sf "$FASTFETCH_LOGO" "$HOME/.local/share/fastfetch/logo.png"
      echo "apply-theme: applied ''${THEME}"
    ''
  );

  setTheme = pkgs.writeShellScriptBin "set-theme" (
    ''
      THEME="''${1:-}"
      STATE="$HOME/.local/state"

      AVAILABLE=$(find ${themesRoot} -mindepth 3 -maxdepth 3 -name "palette-*.nix" \
        -exec basename {} .nix \; 2>/dev/null | sed 's/^palette-//' | sort)

      if [ -z "$THEME" ]; then
        echo "Usage: set-theme <theme>"
        echo "Available themes:"
        echo "$AVAILABLE" | while read slug; do echo "  - $slug"; done
        exit 0
      fi

      if ! echo "$AVAILABLE" | grep -qx "$THEME"; then
        echo "Error: Theme '$THEME' not found in ${themesRoot}"
        exit 1
      fi

      mkdir -p "$STATE"
      echo "$THEME" > "$STATE/theme"

      ${applyThemeScript}/bin/apply-theme "$THEME"

      systemctl --user restart swaybg 2>/dev/null || true
      pkill -USR1 zsh 2>/dev/null || true

      echo "✅ Theme set to: $THEME"
    ''
  );

  # Cycles: main → moon → dawn → lilac-juniper → main
  toggleTheme = pkgs.writeShellScriptBin "toggle-theme" ''
    STATE="$HOME/.local/state/theme"
    CURRENT=$(cat "$STATE" 2>/dev/null || echo "main")
    case "$CURRENT" in
      main|dark)       NEXT="moon" ;;
      moon)            NEXT="dawn" ;;
      dawn|light)      NEXT="lilac-juniper" ;;
      *)               NEXT="main" ;;
    esac
    exec set-theme "$NEXT"
  '';

  # Switches kanshi profile between dual and single monitor mode.
  # State is tracked in ~/.local/state/monitor-mode ("dual" or "single").
  toggleDisplayMode = pkgs.writeShellScriptBin "toggle-display-mode" ''
    STATE="$HOME/.local/state/monitor-mode"
    mkdir -p "$HOME/.local/state"
    CURRENT=$(cat "$STATE" 2>/dev/null || echo "dual")

    if [ "$CURRENT" = "dual" ]; then
      kanshictl switch desktop-solo && echo "single" > "$STATE"
    else
      kanshictl switch desktop-dual && echo "dual" > "$STATE"
    fi
  '';

  mprisWatch = pkgs.writeShellScriptBin "mpris-watch" ''
    export PATH="${lib.makeBinPath [ pkgs.playerctl pkgs.jq pkgs.coreutils pkgs.gnused ]}:$PATH"

    SNARK_FILE="$HOME/.config/waybar/snark.json"
    SNARK_CACHE="''${XDG_RUNTIME_DIR:-/tmp}/mpris-watch-snark"

    STATUS=$(playerctl status 2>/dev/null)
    TITLE=$(playerctl metadata --format '{{title}}' 2>/dev/null)
    ARTIST=$(playerctl metadata --format '{{artist}}' 2>/dev/null)

    if [[ "$STATUS" == "Playing" || "$STATUS" == "Paused" ]] && [[ -n "$TITLE" ]]; then
      rm -f "$SNARK_CACHE"

      # iHeart/terrestrial ICY metadata blob — two formats (same as mpris_status.sh)
      # Format 1: title="Song",artist="Artist",url="song_spot=F" MediaBaseId=...
      # Format 2: Artist - text="Song" song_spot="M" MediaBaseId=...  (M=music, T/C=ad)
      _icy_f1='^title="([^"]*)".*,artist="([^"]*)"'
      _icy_spot=' song_spot="([^"]*)"'
      _icy_text=' text="([^"]*)"'
      is_ad=false
      if [[ "$TITLE" =~ $_icy_f1 ]]; then
        TITLE="''${BASH_REMATCH[1]}"
        [[ -z "$ARTIST" ]] && ARTIST="''${BASH_REMATCH[2]}"
      elif [[ "$TITLE" =~ song_spot= || "$TITLE" =~ MediaBaseId= ]]; then
        icy_spot=""; [[ "$TITLE" =~ $_icy_spot ]] && icy_spot="''${BASH_REMATCH[1]}"
        icy_text=""; [[ "$TITLE" =~ $_icy_text ]] && icy_text="''${BASH_REMATCH[1]}"
        icy_pre="$(echo "$TITLE" | sed 's/ [A-Za-z_][A-Za-z0-9_]*=.*//')"
        icy_pre="''${icy_pre% -}"; icy_pre="''${icy_pre% }"
        if [[ "$icy_spot" == "M" ]]; then
          TITLE="''${icy_text:-$icy_pre}"
          [[ -z "$ARTIST" && -n "$icy_pre" ]] && ARTIST="$icy_pre"
        else
          TITLE="$icy_pre"
          [[ -z "$ARTIST" && -n "$icy_text" ]] && ARTIST="$icy_text"
          is_ad=true
        fi
      fi

      # Fallback: "Artist - Track" packed into title with no separate artist field
      if [[ -z "$ARTIST" && "$TITLE" == *" - "* ]]; then
        ARTIST="''${TITLE%% - *}"
        TITLE="''${TITLE#* - }"
      fi

      AD_MARK=""
      [[ "$is_ad" == true ]] && AD_MARK=" ·ad"

      case "$STATUS" in
        Playing) echo "󰎆 $TITLE — $ARTIST''${AD_MARK}" ;;
        Paused)  echo "󰏤 $TITLE — $ARTIST''${AD_MARK}" ;;
      esac
    else
      if [[ ! -f "$SNARK_CACHE" ]]; then
        jq -r '.mpris.stopped[]' "$SNARK_FILE" 2>/dev/null | shuf -n1 \
          > "$SNARK_CACHE" || echo "The silence judges you." > "$SNARK_CACHE"
      fi
      cat "$SNARK_CACHE"
    fi
  '';

  sqlchPopupPython = pkgs.python3.withPackages (ps: with ps; [
    pygobject3
  ]);

  sqlchPopup = pkgs.writeShellScriptBin "sqlch-popup" ''
    # Toggle: kill running instance, or launch fresh
    if pgrep -f "sqlch-popup.py" > /dev/null 2>&1; then
      pkill -f "sqlch-popup.py"
      exit 0
    fi

    export GI_TYPELIB_PATH="${pkgs.gtk4-layer-shell}/lib/girepository-1.0:${pkgs.gtk4}/lib/girepository-1.0:${pkgs.gdk-pixbuf}/lib/girepository-1.0:${pkgs.pango}/lib/girepository-1.0:${pkgs.graphene}/lib/girepository-1.0:${pkgs.harfbuzz}/lib/girepository-1.0:$GI_TYPELIB_PATH"
    export LD_LIBRARY_PATH="${pkgs.gtk4-layer-shell}/lib:${pkgs.graphene}/lib:$LD_LIBRARY_PATH"
    exec ${sqlchPopupPython}/bin/python3 ${./sqlch-popup.py}
  '';
in
{
  ########################################
  # Niri compositor config + all theme-driven configs — single activation block
  # set-theme calls apply-theme at runtime; this syncs on every nrs.
  ########################################
  home.activation.applyTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${applyThemeScript}/bin/apply-theme
  '';

  ########################################
  # swaybg — wallpaper daemon for all machines
  ########################################
  systemd.user.services.swaybg = {
    Unit = {
      Description = "swaybg wallpaper";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${swaybgLauncher}";
      Restart = "on-failure";
      RestartSec = "2s";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  home.packages = [ pkgs.swaybg pkgs.cava toggleDisplayMode applyThemeScript setTheme toggleTheme sqlchPopup mprisWatch ];

  ########################################
  # XDG portal routing for niri — override the system niri-portals.conf
  # (installed by programs.niri.enable) to explicitly route FileChooser to gtk.
  # Without this, the gnome portal claims FileChooser but refuses dialogs outside
  # a real GNOME session, leaving file pickers empty in browsers and apps.
  ########################################
  xdg.configFile."xdg-desktop-portal/niri-portals.conf".text = ''
    [preferred]
    default=gtk
    org.freedesktop.impl.portal.FileChooser=gtk
    org.freedesktop.impl.portal.Access=gtk
    org.freedesktop.impl.portal.Notification=gtk
    org.freedesktop.impl.portal.Secret=gnome-keyring
    org.freedesktop.impl.portal.Settings=gtk
  '';

  ########################################
  # Suppress GNOME autostart apps that conflict with custom bar modules
  # (blueman-applet and nm-applet autostart via GNOME XDG entries even in niri)
  ########################################
  xdg.configFile."autostart/blueman.desktop".text = "[Desktop Entry]\nHidden=true\n";
  xdg.configFile."autostart/nm-applet.desktop".text = "[Desktop Entry]\nHidden=true\n";

  ########################################
  # Kanshi — dynamic output management
  # Profiles are matched by which connectors are physically connected.
  # Output changes are handled by kanshi; toggle-display-mode switches profiles manually.
  ########################################
  services.kanshi = {
    enable = true;
    settings = [
      # Desktop: both monitors connected and active
      { profile = {
          name = "desktop-dual";
          outputs = [
            { criteria = "DP-4"; status = "enable"; mode = "1920x1080@60.000"; position = "0,0"; scale = 1.0; }
            { criteria = "DP-3"; status = "enable"; mode = "1920x1080@60.000"; position = "1920,0"; scale = 1.0; }
          ];
        };
      }
      # Desktop: manual single-monitor mode — both connected but DP-3 disabled.
      # Named "desktop-solo" so it sorts after "desktop-dual" and is never auto-matched
      # ahead of it; reached only via kanshictl switch (toggle-display-mode).
      { profile = {
          name = "desktop-solo";
          outputs = [
            { criteria = "DP-4"; status = "enable"; mode = "1920x1080@60.000"; position = "0,0"; scale = 1.0; }
            { criteria = "DP-3"; status = "disable"; }
          ];
        };
      }
      # Desktop: only left monitor connected (DP-3 physically unplugged)
      { profile = {
          name = "desktop-single";
          outputs = [
            { criteria = "DP-4"; status = "enable"; mode = "1920x1080@60.000"; position = "0,0"; scale = 1.0; }
          ];
        };
      }
      # Desktop: manual single-monitor mode — DP-4 off, DP-3 as primary at 0,0
      { profile = {
          name = "desktop-single-dp3";
          outputs = [
            { criteria = "DP-4"; status = "disable"; }
            { criteria = "DP-3"; status = "enable"; mode = "1920x1080@60.000"; position = "0,0"; scale = 1.0; }
          ];
        };
      }
      # Surface: internal display only — waybar starts via systemd
      { profile = {
          name = "surface";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; mode = "2736x1824@60.000"; scale = 2.0; }
          ];
        };
      }
    ];
  };

  # Restrict kanshi to niri sessions — hyprland manages its own outputs via monitor.conf
  # mkForce needed because the kanshi HM module already sets ConditionEnvironment = "WAYLAND_DISPLAY"
  systemd.user.services.kanshi.Unit.ConditionEnvironment = lib.mkForce [ "WAYLAND_DISPLAY" "XDG_SESSION_DESKTOP=niri" ];

}
