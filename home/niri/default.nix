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
          inherit family slug wallpaper;
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
    border-radius=7
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
      niriKdl    = pkgs.writeText "niri-config-${slug}.kdl"   (import ./config.kdl.nix { p = t.palette; });
      ironbarCss = pkgs.writeText "ironbar-style-${slug}.css" (import ./ironbar-style.nix t.palette);
      waybarCss  = pkgs.writeText "waybar-style-${slug}.css"  (import ../waybar/style.nix t.palette);
      waybarSh   = pkgs.writeText "waybar-palette-${slug}.sh" t.shContent;
      nemoCss    = pkgs.writeText "nemo-gtk3-${slug}.css"     (import ../nemo/gtk3.css.nix t.palette);
      wofiCss    = pkgs.writeText "wofi-style-${slug}.css"    (mkWofiCss t.palette);
      fuzzelIni  = pkgs.writeText "fuzzel-${slug}.ini"        (mkFuzzelIni t.palette);
      wleaveCss     = pkgs.writeText "wleave-style-${slug}.css"  (mkWleaveCSS t.palette);
      cava          = pkgs.writeText "cava-config-${slug}"       (mkCavaConfig t.palette);
      ghostty       = pkgs.writeText "ghostty-config-${slug}"    (mkGhosttyConfig t.palette);
      pandora       = pkgs.writeText "pandora-${slug}.kdl"       (mkPandoraCfg wallpaper);
      wallpaperPath = wallpaper;
    }
  ) allThemes;

  home = config.home.homeDirectory;

  # swaybg launcher — reads wallpaper path from state file so the
  # systemd service can be restarted with a new image without changing the unit.
  # Uses output '*' to cover all connected outputs (works for both single eDP-1
  # and dual DP-2/DP-3 setups).
  swaybgLauncher = pkgs.writeShellScript "swaybg-launcher" ''
    exec ${pkgs.swaybg}/bin/swaybg -o '*' -i "$(cat "$HOME/.local/state/wallpaper")" -m fill
  '';

  mkPandoraCfg = wallpaper:
    if config.myConfig.isDesktop then ''
      output "DP-3" {
          image "${wallpaper}"
          mode "scroll-vertical"
      }
      output "DP-2" {
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
      border-radius: 6px;
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
        border-radius: 12px;
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
      radius=6
    '';

  setTheme = pkgs.writeShellScriptBin "set-theme" (
    ''
      THEME="''${1:-}"
      STATE="$HOME/.local/state"

      # 1. Dynamically discover themes from the filesystem
      AVAILABLE=$(find ${themesRoot} -mindepth 3 -maxdepth 3 -name "palette-*.nix" \
        -exec basename {} .nix \; 2>/dev/null | sed 's/^palette-//' | sort)

      if [ -z "$THEME" ]; then
        echo "Usage: set-theme <theme>"
        echo "Available themes (filesystem):"
        echo "$AVAILABLE" | while read slug; do
          echo "  - $slug"
        done
        echo ""
        echo "Note: To apply full config changes (Niri, Waybar, etc.), run: nrs"
        exit 0
      fi

      # 2. Check if theme exists in filesystem
      if ! echo "$AVAILABLE" | grep -qx "$THEME"; then
        echo "Error: Theme '$THEME' not found in ${themesRoot}"
        exit 1
      fi

      # 3. Locate theme assets
      THEME_NIX=$(find ${themesRoot} -mindepth 3 -maxdepth 3 -name "palette-$THEME.nix" 2>/dev/null | head -n1)
      THEME_DIR=$(dirname "$THEME_NIX")

      # Prioritize the colorized PNG generated by make-lix-wallpaper.sh
      WALLPAPER=$(ls "$THEME_DIR"/wallpaper-*.png 2>/dev/null | head -n1)

      if [ -z "$WALLPAPER" ]; then
        # Fallback to the SVG only if PNG is missing
        WALLPAPER=$(ls "$THEME_DIR"/*.svg 2>/dev/null | head -n1)
      fi

      echo "Activating theme: $THEME"

      mkdir -p "$STATE"
      echo "$THEME" > "$STATE/theme"

      # ── THE FIX: Update the wallpaper state file and restart swaybg ────────────────
      if [ -n "$WALLPAPER" ]; then
        echo "Applying wallpaper: $WALLPAPER"
        echo "$WALLPAPER" > "$STATE/wallpaper"
        systemctl --user restart swaybg
      else
        echo "⚠️  No wallpaper found in $THEME_DIR"
      fi
      # ───────────────────────────────────────────────────────────────────────────────

      # ── wleave CSS — generated inline from palette.sh ─────────────────────────
      PALETTE_SH=$(find "$THEME_DIR" -name "palette-*.sh" | head -n1)
      if [ -f "$PALETTE_SH" ]; then
        (
          . "$PALETTE_SH"
          mkdir -p "$HOME/.config/wleave"
          cat > "$HOME/.config/wleave/style.css" <<WLEAVECSS
* {
    background-image: none;
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 36px;
}

window {
    background-color: $BASE;
}

button {
    color: $TEXT;
    background-color: $SURFACE;
    border: 2px solid $OVERLAY;
    border-radius: 12px;
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
    background-color: $OVERLAY;
    border-color: $SUBTLE;
    color: $TEXT;
    background-size: 23%;
    outline-style: none;
}

button:focus {
    background-color: $OVERLAY;
    border-color: $IRIS;
    outline-style: none;
}

#lock:hover      { border-color: $FOAM; color: $FOAM; }
#logout:hover    { border-color: $LOVE; color: $LOVE; }
#suspend:hover   { border-color: $IRIS; color: $IRIS; }
#hibernate:hover { border-color: $GOLD; color: $GOLD; }
#shutdown:hover  { border-color: $LOVE; color: $LOVE; }
#reboot:hover    { border-color: $ROSE; color: $ROSE; }
WLEAVECSS
        )
        echo "  → wleave theme applied"
      fi
      # ──────────────────────────────────────────────────────────────────────────

      # Reload Zsh colors (if they source palette.sh)
      pkill -USR1 zsh 2>/dev/null || true

      # Check if generated configs exist (heuristic)
      if [ ! -f "$HOME/.config/niri/config.kdl" ]; then
        echo "⚠️  Warning: Niri config not found. Run 'nrs' to generate configs."
      fi

      echo "✅ State updated. Wallpaper applied."
      echo "   If UI elements didn't change, run: nrs"
    ''
  );

  # Backward-compat cycle wrapper — kept so ironbar/waybar buttons still work
  # while the UI for specific theme selection is being built out.
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

  # Script that symlinks the right ironbar config and switches the kanshi profile.
  # State is tracked in ~/.local/state/monitor-mode ("dual" or "single").
  toggleDisplayMode = pkgs.writeShellScriptBin "toggle-display-mode" ''
    STATE="$HOME/.local/state/monitor-mode"
    mkdir -p "$HOME/.local/state"
    CURRENT=$(cat "$STATE" 2>/dev/null || echo "dual")

    if [ "$CURRENT" = "dual" ]; then
      ln -sf "$HOME/.config/ironbar/config-single.toml" "$HOME/.config/ironbar/config.toml"
      kanshictl switch desktop-solo && echo "single" > "$STATE"
    else
      ln -sf "$HOME/.config/ironbar/config-dual.toml" "$HOME/.config/ironbar/config.toml"
      kanshictl switch desktop-dual && echo "dual" > "$STATE"
      sleep 1 && systemctl --user restart ironbar
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
  # set-theme overwrites at runtime; this block syncs on every nrs.
  ########################################
  home.activation.applyTheme = lib.hm.dag.entryAfter ["writeBoundary"] (
    ''
      THEME=$(cat "$HOME/.local/state/theme" 2>/dev/null || echo "main")
      [ "$THEME" = "dark" ]  && THEME="main"
      [ "$THEME" = "light" ] && THEME="dawn"
      case "$THEME" in
    ''
    + lib.concatStrings (lib.mapAttrsToList (slug: cfgs: ''
        ${slug})
          MAKO_CFG="${cfgs.mako}"
          NIRI_CFG="${cfgs.niriKdl}"
          IRONBAR_CSS="${cfgs.ironbarCss}"
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
          ;;
      '') themeConfigs)
    + ''
        *)
          echo "applyTheme: unknown theme ''${THEME} — run: set-theme main" >&2
          exit 0
          ;;
      esac
      $DRY_RUN_CMD mkdir -p "$HOME/.config/mako"
      $DRY_RUN_CMD rm -f "$HOME/.config/mako/config"
      $DRY_RUN_CMD cp "$MAKO_CFG" "$HOME/.config/mako/config"
      $DRY_RUN_CMD mkdir -p "$HOME/.config/niri"
      $DRY_RUN_CMD rm -f "$HOME/.config/niri/config.kdl"
      $DRY_RUN_CMD cp "$NIRI_CFG" "$HOME/.config/niri/config.kdl"
      $DRY_RUN_CMD rm -f "$HOME/.config/ironbar/style.css"
      $DRY_RUN_CMD cp "$IRONBAR_CSS" "$HOME/.config/ironbar/style.css"
      $DRY_RUN_CMD mkdir -p "$HOME/.config/waybar"
      $DRY_RUN_CMD rm -f "$HOME/.config/waybar/style.css"
      $DRY_RUN_CMD cp "$WAYBAR_CSS" "$HOME/.config/waybar/style.css"
      $DRY_RUN_CMD rm -f "$HOME/.config/waybar/palette.sh"
      $DRY_RUN_CMD cp "$WAYBAR_PALETTE" "$HOME/.config/waybar/palette.sh"
      $DRY_RUN_CMD mkdir -p "$HOME/.config/gtk-3.0"
      $DRY_RUN_CMD cp --remove-destination "$NEMO_CSS" "$HOME/.config/gtk-3.0/gtk.css"
      $DRY_RUN_CMD mkdir -p "$HOME/.config/wofi"
      $DRY_RUN_CMD rm -f "$HOME/.config/wofi/style.css"
      $DRY_RUN_CMD cp "$WOFI_CSS" "$HOME/.config/wofi/style.css"
      $DRY_RUN_CMD mkdir -p "$HOME/.config/fuzzel"
      $DRY_RUN_CMD rm -f "$HOME/.config/fuzzel/fuzzel.ini"
      $DRY_RUN_CMD cp "$FUZZEL_INI" "$HOME/.config/fuzzel/fuzzel.ini"
      $DRY_RUN_CMD mkdir -p "$HOME/.local/state"
      $DRY_RUN_CMD sh -c 'echo "'"$WALLPAPER_PATH"'" > "$HOME/.local/state/wallpaper"'
      $DRY_RUN_CMD mkdir -p "$HOME/.config/cava"
      $DRY_RUN_CMD rm -f "$HOME/.config/cava/config"
      $DRY_RUN_CMD cp "$CAVA_CFG" "$HOME/.config/cava/config"
      $DRY_RUN_CMD mkdir -p "$HOME/.config/ghostty"
      $DRY_RUN_CMD rm -f "$HOME/.config/ghostty/config"
      $DRY_RUN_CMD cp "$GHOSTTY_CFG" "$HOME/.config/ghostty/config"
      $DRY_RUN_CMD mkdir -p "$HOME/.config/wleave"
      $DRY_RUN_CMD rm -f "$HOME/.config/wleave/style.css"
      $DRY_RUN_CMD cp "$WLEAVE_CSS" "$HOME/.config/wleave/style.css"
    ''
  );

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

  ########################################
  # Ironbar status bar
  ########################################
  home.packages = [ pkgs.ironbar pkgs.swaybg pkgs.cava toggleDisplayMode setTheme toggleTheme sqlchPopup mprisWatch ];

  # Two template configs deployed by nix; config.toml is managed by toggle-display-mode.
  xdg.configFile."ironbar/config-dual.toml".source = ./ironbar-dual.toml;
  xdg.configFile."ironbar/config-single.toml".source = ./ironbar-single.toml;


  ########################################
  # Suppress GNOME autostart apps that duplicate custom ironbar modules
  # (blueman-applet and nm-applet autostart via GNOME XDG entries even in niri)
  ########################################
  xdg.configFile."autostart/blueman.desktop".text = "[Desktop Entry]\nHidden=true\n";
  xdg.configFile."autostart/nm-applet.desktop".text = "[Desktop Entry]\nHidden=true\n";

  ########################################
  # Kanshi — dynamic output management
  # Profiles are matched by which connectors are physically connected.
  # Ironbar silently ignores connectors not reported by the compositor,
  # so disabling an output here is enough — no second ironbar config needed
  # for physical changes. The toggle script handles config swaps for manual switching.
  ########################################
  services.kanshi = {
    enable = true;
    settings = [
      # Desktop: both monitors connected and active
      { profile = {
          name = "desktop-dual";
          outputs = [
            { criteria = "DP-2"; status = "enable"; mode = "1920x1080@60.000"; position = "0,0"; scale = 1.0; }
            { criteria = "DP-3"; status = "enable"; mode = "1920x1080@60.000"; position = "1920,0"; scale = 1.0; }
          ];
          exec = [ "systemctl --user restart ironbar" ];
        };
      }
      # Desktop: manual single-monitor mode — both connected but DP-3 disabled.
      # Named "desktop-solo" so it sorts after "desktop-dual" and is never auto-matched
      # ahead of it; reached only via kanshictl switch (toggle-display-mode).
      { profile = {
          name = "desktop-solo";
          outputs = [
            { criteria = "DP-2"; status = "enable"; mode = "1920x1080@60.000"; position = "0,0"; scale = 1.0; }
            { criteria = "DP-3"; status = "disable"; }
          ];
          exec = [ "systemctl --user restart ironbar" ];
        };
      }
      # Desktop: only left monitor connected (DP-3 physically unplugged)
      { profile = {
          name = "desktop-single";
          outputs = [
            { criteria = "DP-2"; status = "enable"; mode = "1920x1080@60.000"; position = "0,0"; scale = 1.0; }
          ];
          exec = [ "systemctl --user restart ironbar" ];
        };
      }
      # Desktop: manual single-monitor mode — DP-2 off, DP-3 as primary at 0,0
      { profile = {
          name = "desktop-single-dp3";
          outputs = [
            { criteria = "DP-2"; status = "disable"; }
            { criteria = "DP-3"; status = "enable"; mode = "1920x1080@60.000"; position = "0,0"; scale = 1.0; }
          ];
          exec = [ "systemctl --user restart ironbar" ];
        };
      }
      # Surface: internal display only — waybar starts via systemd, not ironbar
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
