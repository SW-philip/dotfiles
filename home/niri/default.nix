{ config, pkgs, lib, ... }:
let
  # ── Theme auto-discovery ────────────────────────────────────────────────
  themesRoot = ../../themes;
  l          = import "${themesRoot}/layout.nix";

  allThemes =
    let
      loadTheme = family: folderName:
        let
          dir   = "${themesRoot}/${family}/${folderName}";
          files = builtins.readDir dir;

          nixName = builtins.head (builtins.attrNames (
            lib.filterAttrs (n: _: lib.hasPrefix "palette-" n && lib.hasSuffix ".nix" n) files));
          slug = lib.removeSuffix ".nix" (lib.removePrefix "palette-" nixName);

          shName = builtins.head (builtins.attrNames (
            lib.filterAttrs (n: _: lib.hasPrefix "palette-" n && lib.hasSuffix ".sh" n) files));

          wallpaperFiles = lib.filterAttrs (n: _:
            lib.hasPrefix "wallpaper-" n && lib.hasSuffix ".png" n
          ) files;

          wallpaper = if wallpaperFiles != {}
                      then "${dir}/${builtins.head (builtins.attrNames wallpaperFiles)}"
                      else null;

          p = import "${dir}/${nixName}";
        in {
          inherit family slug wallpaper dir;
          palette   = p;
          shContent = builtins.readFile "${dir}/${shName}";
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

  # Static swaync config.json — palette-independent, only style.css carries colors
  swayncConfig = pkgs.writeText "swaync-config.json" ''
    {
      "positionX": "right",
      "positionY": "top",
      "control-center-margin-top": 8,
      "control-center-margin-bottom": 8,
      "control-center-margin-right": 8,
      "control-center-margin-left": 0,
      "notification-icon-size": 48,
      "notification-body-image-height": 100,
      "notification-body-image-width": 200,
      "timeout": 5,
      "timeout-low": 3,
      "timeout-critical": 0,
      "fit-to-screen": false,
      "control-center-width": 500,
      "notification-window-width": 400,
      "keyboard-shortcuts": true,
      "image-visibility": "when-available",
      "transition-time": 100,
      "hide-on-clear": false,
      "hide-on-action": true,
      "script-fail-notify": true,
      "scripts": {},
      "notification-visibility": {},
      "widgets": ["title", "notifications"],
      "widget-config": {
        "title": {
          "text": "Notifications",
          "clear-all-button": true,
          "button-text": "Clear All"
        },
        "notifications": {}
      }
    }
  '';

  mkSwayncCss = p: ''
    * {
      font-family: "JetBrains Mono", monospace;
      font-size: 12px;
    }

    .notification-row {
      outline: none;
    }

    .notification-row:focus,
    .notification-row:hover {
      background: none;
    }

    .notification {
      background: ${p.SURFACE};
      border: 2px solid ${p.SHADOW};
      border-radius: ${toString (l.radiusSm + 1)}px;
      box-shadow: 3px 4px 0 0 ${p.SHADOW};
      margin: 6px 12px;
      padding: 0;
    }

    .notification-content {
      background: transparent;
      padding: 8px 12px;
      border-radius: ${toString l.radiusSm}px;
    }

    .notification-default-action,
    .notification-action {
      padding: 4px;
      background: transparent;
      border: none;
      color: ${p.TEXT};
      border-radius: ${toString l.radiusSm}px;
    }

    .notification-default-action:hover,
    .notification-action:hover {
      background: ${p.OVERLAY};
      color: ${p.TEXT};
    }

    .close-button {
      background: transparent;
      color: ${p.MUTED};
      border: none;
      border-radius: ${toString l.radiusSm}px;
      padding: 2px;
    }

    .close-button:hover {
      color: ${p.LOVE};
      background: ${p.OVERLAY};
    }

    .summary {
      font-size: 13px;
      font-weight: 700;
      color: ${p.TEXT};
      text-shadow: 1px 2px 0 ${p.SHADOW};
    }

    .time {
      font-size: 11px;
      font-weight: 600;
      color: ${p.MUTED};
    }

    .body {
      font-size: 12px;
      font-weight: 600;
      color: ${p.TEXT};
      text-shadow: 1px 2px 0 ${p.SHADOW};
    }

    .app-icon-image {
      border-radius: ${toString l.radiusSm}px;
      box-shadow: 1px 2px 0 0 ${p.SHADOW};
    }

    .notification.critical {
      background: ${p.TINT_CRITICAL_BG};
      border-color: ${p.CRITICAL};
    }

    .notification.critical .summary {
      color: ${p.CRITICAL};
    }

    .control-center {
      background: ${p.BASE};
      border: 2px solid ${p.SHADOW};
      border-radius: ${toString l.radiusLg}px;
      box-shadow: 4px 5px 0 0 ${p.SHADOW};
    }

    .control-center-list {
      background: transparent;
    }

    .control-center-list .notification {
      margin: 4px 8px;
    }

    #label-count {
      font-weight: 700;
      color: ${p.LOVE};
    }
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
      subtleBorder      = if t.isLight then "#0000000a" else "#ffffff0a";
      faintBorder       = if t.isLight then "#00000006" else "#ffffff06";
      wallpaperFallback = if t.isLight then "${home}/Images/rothkos_dawn_tall.png"
                          else "${home}/Images/rothkos_moon_tall.png";
      # wallpaper-*.png files are gitignored so builtins.readDir never sees them;
      # record the live FS dir so apply-theme can find them at runtime instead.
      wallpaperLiveDir  = "${home}/nixos/themes/${t.family}/${builtins.baseNameOf t.dir}";
      # pandora config still needs a path baked in — use fallback since PNGs aren't in store
      pandoraWallpaper  = wallpaperFallback;
    in {
      swayncCss  = pkgs.writeText "swaync-style-${slug}.css"  (mkSwayncCss t.palette);
      niriKdl    = pkgs.writeText "niri-config-${slug}.kdl"   (import ./config.kdl.nix { p = t.palette; inherit l; cursorSize = if config.myConfig.isDesktop then 24 else 48; isDesktop = config.myConfig.isDesktop; toggleWvkbdBin = "${toggleWvkbd}/bin/toggle-wvkbd"; });
      waybarCss  = pkgs.writeText "waybar-style-${slug}.css"  (import ../waybar/style.nix { p = t.palette; inherit l; });
      waybarSh   = pkgs.writeText "waybar-palette-${slug}.sh" t.shContent;
      nemoCss    = pkgs.writeText "nemo-gtk3-${slug}.css"     (import ../nemo/gtk3.css.nix t.palette);
      wofiCss    = pkgs.writeText "wofi-style-${slug}.css"    (mkWofiCss t.palette);
      fuzzelIni  = pkgs.writeText "fuzzel-${slug}.ini"        (mkFuzzelIni t.palette);
      wleaveCss     = pkgs.writeText "wleave-style-${slug}.css"  (mkWleaveCSS t.palette);
      cava          = pkgs.writeText "cava-config-${slug}"       (mkCavaConfig t.palette);
      ghostty       = pkgs.writeText "ghostty-config-${slug}"    (mkGhosttyConfig t.palette);
      hyprlockConf  = pkgs.writeText "hyprlock-${slug}.conf"     (mkHyprlock t.palette);
      librewolfCss  = pkgs.writeText "librewolf-chrome-${slug}.css" (import ../librewolf/userChrome.css.nix t.palette);
      pandora       = pkgs.writeText "pandora-${slug}.kdl"       (mkPandoraCfg pandoraWallpaper);
      inherit wallpaperFallback wallpaperLiveDir;
      fastfetchLogo = mkFastfetchLogo t;
    }
  ) allThemes;

  home = config.home.homeDirectory;

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

    window-padding-x = 14
    window-padding-y = 10
  '';

  mkWofiCss = p: ''
    window {
      background-color: ${p.OVERLAY};
      font-family: "JetBrainsMono Nerd Font";
      font-size: 12px;
      border: 2px solid ${p.SHADOW};
      box-shadow: 3px 4px 0 0 ${p.SHADOW};
    }

    #entry {
      margin: 5px;
      padding: 8px;
      border-radius: ${toString l.radiusSm}px;
      background-color: ${p.OVERLAY};
      color: ${p.TEXT};
    }

    #entry:selected {
      background-color: ${p.HIGHLIGHT_MED};
      color: ${p.PINE};
    }

    #input {
      background-color: ${p.SURFACE};
      color: ${p.TEXT};
      border: 2px solid ${p.SHADOW};
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
        border: 2px solid ${p.SHADOW};
        border-radius: ${toString l.radiusLg}px;
        margin: 8px;
        outline-style: none;
        box-shadow: 3px 4px 0 0 ${p.SHADOW};
        text-shadow: none;
        background-repeat: no-repeat;
        background-position: center 35%;
        background-size: 20%;
        transition: all 0.2s ease-in-out;
    }

    button:hover {
        background-color: ${p.OVERLAY};
        border-color: ${p.SHADOW};
        box-shadow: 2px 3px 0 0 ${p.SHADOW};
        color: ${p.TEXT};
        background-size: 23%;
        outline-style: none;
    }

    button:focus {
        background-color: ${p.OVERLAY};
        border-color: ${p.IRIS};
        box-shadow: 2px 3px 0 0 ${p.SHADOW};
        outline-style: none;
    }
  '';

  mkFuzzelIni = p:
    let c = hex: (lib.removePrefix "#" hex) + "ff";
    in ''
      [main]
      font=monospace:size=13
      dpi-aware=auto
      terminal=ghostty -e
      layer=overlay
      show-actions=no
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
      width=2
      radius=${toString l.radiusSm}
    '';

  mkHyprlock = p:
    let
      h          = col: lib.removePrefix "#" col;
      isLight    = (p.FONT_SIZE_BAR or "12px") == "13px";
      brightness = if isLight then "0.15" else "0.08";
      configHome = config.xdg.configHome;
      cacheHome  = config.xdg.cacheHome;
    in ''
      general {
          disable_loading    = true
          hide_cursor        = true
          no_fade_in         = false
          fractional_scaling = 1
      }

      background {
          path        = screenshot
          blur_passes = 0
          brightness  = ${brightness}
          contrast    = 0.9
      }

      image {
          path         = ${cacheHome}/sqlch/covers/current.jpg
          reload_time  = 2
          reload_cmd   = ${configHome}/waybar/scripts/hyprlock_art.sh
          size         = 380
          rounding     = 8
          border_size  = 5
          border_color = rgba(${h p.IRIS}ff)
          position     = 0, 0
          halign       = center
          valign       = center
      }

      label {
          text        = cmd[update:1000] quantum-clock 2>/dev/null | jq -r '.text // "--:--"'
          color       = rgba(000000ff)
          font_size   = 64
          font_family = JetBrainsMono Nerd Font ExtraBold
          position    = 2, 283
          halign      = center
          valign      = center
      }
      label {
          text        = cmd[update:1000] quantum-clock 2>/dev/null | jq -r '.text // "--:--"'
          color       = rgba(${h p.GOLD}ff)
          font_size   = 64
          font_family = JetBrainsMono Nerd Font ExtraBold
          position    = 0, 285
          halign      = center
          valign      = center
      }

      label {
          text        = cmd[update:60000] date +"%A, %d %B"
          color       = rgba(000000ff)
          font_size   = 24
          font_family = JetBrainsMono Nerd Font
          position    = 2, 220
          halign      = center
          valign      = center
      }
      label {
          text        = cmd[update:60000] date +"%A, %d %B"
          color       = rgba(${h p.FOAM}ff)
          font_size   = 24
          font_family = JetBrainsMono Nerd Font
          position    = 0, 222
          halign      = center
          valign      = center
      }

      label {
          text        = cmd[update:2000] ${configHome}/waybar/scripts/mpris_status.sh 2>/dev/null | jq -r '.text // ""'
          color       = rgba(000000ff)
          font_size   = 24
          font_family = JetBrainsMono Nerd Font
          position    = 2, -217
          halign      = center
          valign      = center
      }
      label {
          text        = cmd[update:2000] ${configHome}/waybar/scripts/mpris_status.sh 2>/dev/null | jq -r '.text // ""'
          color       = rgba(${h p.TEXT}ff)
          font_size   = 24
          font_family = JetBrainsMono Nerd Font
          position    = 0, -215
          halign      = center
          valign      = center
      }

      label {
          text        = cmd[update:2000] ${configHome}/waybar/scripts/mpris_status.sh 2>/dev/null | jq -r '(.tooltip // "") | split("\n") | .[0]'
          color       = rgba(${h p.SUBTLE}cc)
          font_size   = 24
          font_family = JetBrainsMono Nerd Font
          position    = 0, -242
          halign      = center
          valign      = center
      }

      label {
          text        = cmd[update:300000] waybar-weather --mode default 2>/dev/null | jq -r '.text // ""'
          color       = rgba(000000ff)
          font_size   = 24
          font_family = JetBrainsMono Nerd Font
          position    = 2, 73
          halign      = center
          valign      = bottom
      }
      label {
          text        = cmd[update:300000] waybar-weather --mode default 2>/dev/null | jq -r '.text // ""'
          color       = rgba(${h p.ROSE}ff)
          font_size   = 24
          font_family = JetBrainsMono Nerd Font
          position    = 0, 75
          halign      = center
          valign      = bottom
      }

      label {
          text        = cmd[update:300000] waybar-weather --mode forecast 2>/dev/null | jq -r '.text // ""'
          color       = rgba(${h p.SUBTLE}d9)
          font_size   = 24
          font_family = JetBrainsMono Nerd Font
          position    = 0, 30
          halign      = center
          valign      = bottom
      }

      input-field {
          size              = 320, 52
          outline_thickness = 4
          dots_size         = 0.25
          dots_spacing      = 0.35
          dots_center       = true
          outer_color       = rgba(${h p.IRIS}ff)
          inner_color       = rgba(${h p.BASE}fa)
          font_color        = rgba(${h p.TEXT}ff)
          fade_on_empty     = true
          rounding          = 6
          check_color       = rgb(${h p.GOLD})
          fail_color        = rgb(${h p.LOVE})
          placeholder_text  =
          hide_input        = false
          position          = 0, 215
          halign            = center
          valign            = bottom
      }
    '';

  applyThemeScript = pkgs.writeShellScriptBin "apply-theme" (
    ''
      THEME="''${1:-$(cat "$HOME/.local/state/theme" 2>/dev/null || echo "main")}"
      [ "$THEME" = "dark" ]  && THEME="main"
      [ "$THEME" = "light" ] && THEME="dawn"
      case "$THEME" in
    ''
    + lib.concatStrings (lib.mapAttrsToList (slug: cfgs: ''
        ${slug})
          SWAYNC_CSS="${cfgs.swayncCss}"
          NIRI_CFG="${cfgs.niriKdl}"
          WAYBAR_CSS="${cfgs.waybarCss}"
          WAYBAR_PALETTE="${cfgs.waybarSh}"
          NEMO_CSS="${cfgs.nemoCss}"
          WOFI_CSS="${cfgs.wofiCss}"
          FUZZEL_INI="${cfgs.fuzzelIni}"
          PANDORA_CFG="${cfgs.pandora}"
          WALLPAPER_DIR="${cfgs.wallpaperLiveDir}"
          WALLPAPER_FALLBACK="${cfgs.wallpaperFallback}"
          WLEAVE_CSS="${cfgs.wleaveCss}"
          CAVA_CFG="${cfgs.cava}"
          GHOSTTY_CFG="${cfgs.ghostty}"
          FASTFETCH_LOGO="${cfgs.fastfetchLogo}"
          LIBREWOLF_CSS="${cfgs.librewolfCss}"
          HYPRLOCK_CFG="${cfgs.hyprlockConf}"
          ;;
      '') themeConfigs)
    + ''
        *)
          echo "apply-theme: unknown theme ''${THEME}" >&2
          exit 1
          ;;
      esac
      mkdir -p "$HOME/.config/swaync"
      cp --remove-destination "${swayncConfig}" "$HOME/.config/swaync/config.json"
      cp --remove-destination "$SWAYNC_CSS" "$HOME/.config/swaync/style.css"
      mkdir -p "$HOME/.config/niri"
      cp --remove-destination "$NIRI_CFG" "$HOME/.config/niri/config.kdl"
      mkdir -p "$HOME/.config/waybar"
      cp --remove-destination "$WAYBAR_CSS" "$HOME/.config/waybar/style.css"
      cp --remove-destination "$WAYBAR_PALETTE" "$HOME/.config/waybar/palette.sh"
      mkdir -p "$HOME/.config/gtk-3.0"
      cp --remove-destination "$NEMO_CSS" "$HOME/.config/gtk-3.0/gtk.css"
      mkdir -p "$HOME/.config/wofi"
      cp --remove-destination "$WOFI_CSS" "$HOME/.config/wofi/style.css"
      mkdir -p "$HOME/.config/fuzzel"
      cp --remove-destination "$FUZZEL_INI" "$HOME/.config/fuzzel/fuzzel.ini"
      mkdir -p "$HOME/.local/state"
      WALLPAPER_PATH=$(find "$WALLPAPER_DIR" -maxdepth 1 -name "wallpaper-*.png" 2>/dev/null | sort | head -1)
      if [ -z "$WALLPAPER_PATH" ]; then WALLPAPER_PATH="$WALLPAPER_FALLBACK"; fi
      echo "$WALLPAPER_PATH" > "$HOME/.local/state/wallpaper"
      mkdir -p "$HOME/.config/cava"
      cp --remove-destination "$CAVA_CFG" "$HOME/.config/cava/config"
      mkdir -p "$HOME/.config/ghostty"
      cp --remove-destination "$GHOSTTY_CFG" "$HOME/.config/ghostty/config"
      mkdir -p "$HOME/.config/wleave"
      cp --remove-destination "$WLEAVE_CSS" "$HOME/.config/wleave/style.css"
      mkdir -p "$HOME/.config/hypr"
      cp --remove-destination "$HYPRLOCK_CFG" "$HOME/.config/hypr/hyprlock.conf"
      mkdir -p "$HOME/.local/share/fastfetch"
      ln -sf "$FASTFETCH_LOGO" "$HOME/.local/share/fastfetch/logo.png"
      while IFS='=' read -r _key _val; do
        _val="''${_val%$'\r'}"
        [ "$_key" = "Path" ] && {
          mkdir -p "$HOME/.librewolf/$_val/chrome"
          cp --remove-destination "$LIBREWOLF_CSS" "$HOME/.librewolf/$_val/chrome/userChrome.css"
        }
      done < "$HOME/.librewolf/profiles.ini" 2>/dev/null || {
        mkdir -p "$HOME/.librewolf/default/chrome"
        cp --remove-destination "$LIBREWOLF_CSS" "$HOME/.librewolf/default/chrome/userChrome.css"
      }
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
      pkill -SIGUSR1 waybar 2>/dev/null || true
      swaync-client -R 2>/dev/null || true
      sleep 0.3
      pkill -f waybar-weather 2>/dev/null || true
      pkill -SIGUSR2 waybar 2>/dev/null || true
      pkill -SIGUSR2 ghostty 2>/dev/null || true

      echo "✅ Theme set to: $THEME"
    ''
  );

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

  toggleWvkbd = pkgs.writeShellScriptBin "toggle-wvkbd" ''
    ${pkgs.systemd}/bin/systemctl --user is-active --quiet wvkbd \
      && ${pkgs.systemd}/bin/systemctl --user stop wvkbd \
      || ${pkgs.systemd}/bin/systemctl --user start wvkbd
  '';

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

  home.activation.applyTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${applyThemeScript}/bin/apply-theme
    ${pkgs.niri}/bin/niri msg action load-config-file 2>/dev/null || true
  '';

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

  home.packages = [ pkgs.swaybg pkgs.cava toggleDisplayMode applyThemeScript setTheme toggleTheme sqlchPopup mprisWatch toggleWvkbd ];

  xdg.configFile."xdg-desktop-portal/niri-portals.conf".text = ''
    [preferred]
    default=gtk
    org.freedesktop.impl.portal.FileChooser=gtk
    org.freedesktop.impl.portal.Access=gtk
    org.freedesktop.impl.portal.Notification=gtk
    org.freedesktop.impl.portal.Secret=gnome-keyring
    org.freedesktop.impl.portal.Settings=gtk
  '';

  xdg.configFile."autostart/blueman.desktop".text = "[Desktop Entry]\nHidden=true\n";
  xdg.configFile."autostart/nm-applet.desktop".text = "[Desktop Entry]\nHidden=true\n";

  services.kanshi = {
    enable = true;
    settings = [
      { profile = {
          name = "desktop-dual";
          outputs = [
            { criteria = "DP-4"; status = "enable"; mode = "1920x1080@60.000"; position = "0,0"; scale = 1.0; }
            { criteria = "DP-3"; status = "enable"; mode = "1920x1080@60.000"; position = "1920,0"; scale = 1.0; }
          ];
        };
      }
      { profile = {
          name = "desktop-solo";
          outputs = [
            { criteria = "DP-4"; status = "enable"; mode = "1920x1080@60.000"; position = "0,0"; scale = 1.0; }
            { criteria = "DP-3"; status = "disable"; }
          ];
        };
      }
      { profile = {
          name = "desktop-single";
          outputs = [
            { criteria = "DP-4"; status = "enable"; mode = "1920x1080@60.000"; position = "0,0"; scale = 1.0; }
          ];
        };
      }
      { profile = {
          name = "desktop-single-dp3";
          outputs = [
            { criteria = "DP-4"; status = "disable"; }
            { criteria = "DP-3"; status = "enable"; mode = "1920x1080@60.000"; position = "0,0"; scale = 1.0; }
          ];
        };
      }
      { profile = {
          name = "surface";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; mode = "2736x1824@60.000"; scale = 2.0; }
          ];
        };
      }
    ];
  };

  systemd.user.services.kanshi.Unit.ConditionEnvironment = lib.mkForce [ "WAYLAND_DISPLAY" "XDG_SESSION_DESKTOP=niri" ];

}
