# profiles/home/base.nix
# Universal home config — shared across all hosts.
{ inputs, pkgs, lib, config, ... }:
let
  helium = inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # ── Bibata Modern Ice Cursor (Built from Source) ──
  bibata-modern-ice = pkgs.stdenv.mkDerivation {
    pname = "bibata-modern-ice-cursor";
    version = "2.0.4";

    src = pkgs.fetchFromGitHub {
      owner = "ful1e5";
      repo = "Bibata_Cursor";
      rev = "v2.0.4";
      # ⚠️ You will need to update the sha256 hash below after the first run fails again
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };

    # No postPatch needed, we build from source
    buildInputs = [ pkgs.nodejs pkgs.yarn ]; # Required for the build script

    buildPhase = ''
      # Install dependencies and build the themes
      yarn install
      yarn build
    '';

    installPhase = ''
      mkdir -p $out/share/hyprcursor

      # The build script creates folders like 'Bibata-Modern-Ice' in the root
      # We need to find the Hyprcursor output folder
      if [ -d "Hyprcursor/Bibata-Modern-Ice" ]; then
        cp -r Hyprcursor/Bibata-Modern-Ice $out/share/hyprcursor/
      elif [ -d "Bibata-Modern-Ice" ]; then
        cp -r Bibata-Modern-Ice $out/share/hyprcursor/
      else
        # Fallback: look for any folder starting with Bibata
        find . -maxdepth 1 -type d -name "Bibata-*" -exec cp -r {} $out/share/hyprcursor/ \;
      fi
    '';

    meta = {
      description = "Bibata Modern Ice Cursor Theme (Built from Source)";
      homepage = "https://github.com/ful1e5/Bibata_Cursor";
      license = pkgs.lib.licenses.mit;
    };
  };

  pythonEnv = pkgs.python312.withPackages (ps: with ps; [
    # UI / TUI
    pygobject3 textual rich pystray pillow pydbus cairosvg
    # Networking / data
    requests watchdog python-dateutil
    # Infra / logging
    loguru platformdirs attrs typing-extensions
    # Build tooling
    build setuptools wheel pyyaml
  ]);
in
{
  imports = [
    ../../modules/home-options.nix
    ../../home/waybar
    ../../home/mako
    ../../home/niri
    # ../../home/hypr
    ../packages/fastfetch.nix
  ];

  ########################################
  # Session / GTK
  ########################################
  gtk = {
    enable = true;
    gtk4.theme = config.gtk.theme;
    theme = {
      name    = "rose-pine-moon-gtk";
      package = pkgs.rose-pine-gtk-theme;
    };
    iconTheme = {
      name    = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    cursorTheme = {
      name    = "Bibata-Modern-Ice";
      package = bibata-modern-ice;
      size    = 24;
    };
  };

  xdg.portal.config.common.default = "*";

  # Register .nix and .conf as distinct mimetypes so file managers icon them separately.
  xdg.dataFile."mime/packages/custom-dev.xml".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
      <mime-type type="text/x-nix">
        <comment>Nix expression</comment>
        <glob pattern="*.nix"/>
        <sub-class-of type="text/plain"/>
      </mime-type>
      <mime-type type="text/x-conf">
        <comment>Configuration file</comment>
        <glob pattern="*.conf"/>
        <sub-class-of type="text/plain"/>
      </mime-type>
    </mime-info>
  '';

  # Copy Papirus-Dark to a writable local path, tint folders violet (IRIS),
  # and wire up icons for custom mimetypes. Re-runs when the package changes.
  home.activation.papirus-violet = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="${pkgs.gawk}/bin:${pkgs.coreutils}/bin:$PATH"
    _ICONS="$HOME/.local/share/icons"
    _THEME="$_ICONS/Papirus-Dark"
    _SRC="${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark"
    _STAMP="$_ICONS/.papirus-dark-src"
    if [ "$(cat "$_STAMP" 2>/dev/null)" != "${pkgs.papirus-icon-theme}" ]; then
      $DRY_RUN_CMD rm -rf "$_THEME"
      $DRY_RUN_CMD cp -rL "$_SRC" "$_THEME"
      $DRY_RUN_CMD chmod -R u+w "$_THEME"
      $DRY_RUN_CMD ${pkgs.papirus-folders}/bin/papirus-folders -C violet -t Papirus-Dark
      # .nix → lambda/functional feel (Haskell icon); .conf → gear/config feel
      for _SIZE in 16x16 22x22 24x24 32x32 48x48 64x64; do
        _DIR="$_THEME/$_SIZE/mimetypes"
        [ -d "$_DIR" ] || continue
        $DRY_RUN_CMD ln -sf text-x-haskell.svg      "$_DIR/text-x-nix.svg"
        $DRY_RUN_CMD ln -sf text-x-systemd-unit.svg "$_DIR/text-x-conf.svg"
      done
      $DRY_RUN_CMD printf '%s' "${pkgs.papirus-icon-theme}" > "$_STAMP"
    fi
    # Update user mime database so file managers see the new types.
    $DRY_RUN_CMD ${pkgs.shared-mime-info}/bin/update-mime-database \
      "$HOME/.local/share/mime"
  '';

  home.stateVersion = "25.11";
  home.sessionPath = [ "$HOME/.local/bin" ];

  ########################################
  # systemd user services
  ########################################
  systemd.user.startServices = "sd-switch";

  systemd.user.services = {
    sqlch-daemon = {
      Unit = {
        Description = "sqlch mpris daemon";
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.bash}/bin/bash -c 'set -a; . /run/secrets/spotify_env; set +a; exec ${pkgs.sqlch}/bin/sqlch daemon'";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    protonmail-bridge = {
      Unit = {
        Description = "Proton Mail Bridge";
        After = [ "network-online.target" "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # cliphist: watch the clipboard and store history in ~/.cache/cliphist/
    # Two watchers — one for text, one for images
    cliphist-text = {
      Unit = {
        Description = "cliphist text clipboard watcher";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    cliphist-image = {
      Unit = {
        Description = "cliphist image clipboard watcher";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };

  ########################################
  # Shell
  ########################################
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 50000;
      save = 50000;
      extended = true;
      ignoreDups = true;
      ignoreAllDups = true;
      expireDuplicatesFirst = true;
      share = true;
    };

    shellAliases = {
      ls = "eza --icons=auto --group-directories-first";
      ll = "eza -lh --icons=auto --group-directories-first --git";
      la = "eza -lah --icons=auto --group-directories-first --git";
      lt = "eza --tree --icons=auto --level=2";
      ltt = "eza --tree --icons=auto";
      cat = "bat --style=plain --paging=never";
      lg = "lazygit";
      gds = "git diff --staged";
      lb = "sudo rm -f /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI";
      nrs = "sudo nixos-rebuild switch --flake";
      nrb = "sudo nixos-rebuild boot --flake";
      nrt = "sudo nixos-rebuild test --flake";
      nfu = "nix flake update";
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";
      grep = "grep --color=auto";
      ip = "ip --color=auto";
      diff = "delta";
      gen-theme = "${pythonEnv}/bin/python3 ~/nixos/tools/theme-gen.py";
      harmonize = "bash ~/nixos/tools/harmonize-themes.sh";
    };

    oh-my-zsh = {
      enable = true;
      # Removed "fzf" from here so it doesn't fight our custom color logic
      plugins = [ "git" "sudo" "zoxide" "extract" "copypath" "copyfile" ];
    };

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "you-should-use";
        src = pkgs.zsh-you-should-use;
        file = "share/zsh/plugins/you-should-use/you-should-use.plugin.zsh";
      }
      {
        name = "autopair";
        src = pkgs.zsh-autopair;
        file = "share/zsh/zsh-autopair/autopair.zsh";
      }
    ];

    # Using mkAfter ensures this block is at the BOTTOM of .zshrc
    # This prevents Oh-My-Zsh or plugins from overwriting your colors.
    initContent = lib.mkAfter ''
      # 1. Color Refresh Function
      _refresh_colors() {
        # Path where toggle-theme copies the palette
        PALETTE_FILE="$HOME/.config/waybar/palette.sh"

        if [ -f "$PALETTE_FILE" ]; then
          source "$PALETTE_FILE"

          # Export variables for fzf/subshells
          export BASE SURFACE OVERLAY MUTED SUBTLE TEXT LOVE GOLD ROSE PINE FOAM IRIS \
                 HIGHLIGHT_LOW HIGHLIGHT_MED HIGHLIGHT_HIGH

          # Re-apply FZF options with the new palette values
          export FZF_DEFAULT_OPTS="
            --height=50% --layout=reverse --border=rounded
            --info=inline --cycle
            --bind=ctrl-u:preview-page-up,ctrl-d:preview-page-down
            --bind=ctrl-/:toggle-preview
            --color=bg:''${BASE},bg+:''${HIGHLIGHT_LOW},fg:''${TEXT},fg+:''${TEXT}
            --color=hl:''${LOVE},hl+:''${LOVE},info:''${FOAM},prompt:''${IRIS}
            --color=pointer:''${LOVE},marker:''${GOLD},spinner:''${FOAM},header:''${MUTED}
            --color=border:''${HIGHLIGHT_MED},gutter:''${BASE}
          "

          # Update syntax highlighting for comments
          if [[ -v ZSH_HIGHLIGHT_STYLES ]]; then
            ZSH_HIGHLIGHT_STYLES[comment]="fg=''${MUTED:-#6e6a86}"
          fi
        fi
      }

      # 2. Initialize colors on shell startup
      _refresh_colors

      # 3. The Signal Trap (Reactive Theme Switching)
      # This responds to 'pkill -USR1 zsh' from your toggle-theme script
      TRAPUSR1() {
        _refresh_colors
        # Force prompt redraw so colors update without pressing Enter
        zle && zle reset-prompt
      }

      # 4. Final Sourcing & Bindings
      [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
      [ -f "$HOME/.config/sqlch/env" ] && source "$HOME/.config/sqlch/env"

      ${pkgs.nix-your-shell}/bin/nix-your-shell zsh | source /dev/stdin

      zstyle ':completion:*' menu select
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
      zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
      zstyle ':completion:*:warnings' format '%F{red}no matches%f'
      zstyle ':completion:*' group-name ""
      zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"

      bindkey "^[[1;5C" forward-word
      bindkey "^[[1;5D" backward-word
      bindkey "^[[H"    beginning-of-line
      bindkey "^[[F"    end-of-line
      bindkey "^[[3~"   delete-char
      bindkey "^H"      backward-kill-word
      bindkey "^[[3;5~" kill-word

      mkcd() { mkdir -p "$1" && cd "$1" }
      nsh() { nix shell ''${@/#/nixpkgs#} }
    '';
  };

  # ── atuin: SQLite-powered shell history with fuzzy TUI (ctrl+r) ──
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      style                            = "compact";
      search_mode                       = "fuzzy";
      filter_mode_shell_up_key_binding = "session";
      show_preview                     = true;
      inline_height                    = 20;
    };
  };

  # ── direnv: auto-load .envrc per directory; nix-direnv for nix develop ──
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        disable_loading    = true;
        hide_cursor        = true;
        no_fade_in         = false;
        fractional_scaling = 1;
      };

      background = [
        {
          path        = "screenshot";
          blur_passes = 3;
          blur_size   = 8;
        }
      ];

      image = [
        {
          path        = "${config.xdg.cacheHome}/sqlch/covers/current.jpg";
          reload_time = 2;
          reload_cmd  = "${config.xdg.configHome}/waybar/scripts/hyprlock_art.sh";
          size        = 380;
          rounding    = 20;
          border_size = 0;
          position    = "0, 0";
          halign      = "center";
          valign      = "center";
        }
      ];

      label = [
        {
          text        = "cmd[update:1000] quantum-clock 2>/dev/null | jq -r '.text // \"--:--\"'";
          color       = "rgba(224, 222, 244, 1.0)";
          font_size   = 64;
          font_family = "JetBrainsMono Nerd Font ExtraBold";
          position    = "0, 285";
          halign      = "center";
          valign      = "center";
        }
        {
          text        = "cmd[update:60000] echo \"$(date +\"%A, %d %B\")\"";
          color       = "rgba(144, 140, 170, 0.85)";
          font_size   = 24;
          font_family = "JetBrainsMono Nerd Font";
          position    = "0, 222";
          halign      = "center";
          valign      = "center";
        }
        {
          text        = "cmd[update:2000] ${config.xdg.configHome}/waybar/scripts/mpris_status.sh 2>/dev/null | jq -r '.text // \"\"'";
          color       = "rgba(224, 222, 244, 0.95)";
          font_size   = 24;
          font_family = "JetBrainsMono Nerd Font";
          position    = "0, -215";
          halign      = "center";
          valign      = "center";
        }
        {
          text        = "cmd[update:2000] ${config.xdg.configHome}/waybar/scripts/mpris_status.sh 2>/dev/null | jq -r '(.tooltip // \"\") | split(\"\\n\") | .[0]'";
          color       = "rgba(144, 140, 170, 0.75)";
          font_size   = 24;
          font_family = "JetBrainsMono Nerd Font";
          position    = "0, -242";
          halign      = "center";
          valign      = "center";
        }
        {
            text        = "cmd[update:300000] waybar-weather --mode default 2>/dev/null | jq -r '.text // \"\"'";
            color       = "rgba(224, 222, 244, 0.9)";
            font_size   = 24;
            font_family = "JetBrainsMono Nerd Font";
            position    = "0, 75";
            halign      = "center";
            valign      = "bottom";
          }
          {
            text        = "cmd[update:300000] waybar-weather --mode forecast 2>/dev/null | jq -r '.text // \"\"'";
            color       = "rgba(144, 140, 170, 0.85)";
            font_size   = 24;
            font_family = "JetBrainsMono Nerd Font";
            position    = "0, 30";
            halign      = "center";
            valign      = "bottom";
          }
      ];

      input-field = [
        {
          size              = "320, 52";
          outline_thickness = 2;
          dots_size         = 0.22;
          dots_spacing      = 0.35;
          dots_center       = true;
          outer_color       = "rgba(196, 167, 231, 1.0)";
          inner_color       = "rgba(20, 18, 36, 0.85)";
          font_color        = "rgb(224, 222, 244)";
          fade_on_empty      = true;
          rounding          = -1;
          check_color       = "rgb(246, 193, 119)";
          fail_color        = "rgb(235, 111, 146)";
          placeholder_text  = "";
          hide_input        = false;
          position          = "0, 215";
          halign            = "center";
          valign            = "bottom";
        }
      ];
    };
  };

  ########################################
  # Programs
  ########################################
  programs = {
    mpv = {
      enable  = true;
      scripts = [ pkgs.mpvScripts.mpris ];
    };

    btop.enable      = true;
    yazi = { enable = true; shellWrapperName = "yy"; };
    zoxide.enable    = true;
    fzf.enable       = true;
    firefox.enable   = true;
    gpg.enable       = true;
  };

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-gnome3;
  };

  ########################################
  # Services
  ########################################
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "";
        ignore_dbus_inhibit = false;
      };
      listener = [
        {
          timeout = 240;
          on-timeout = "${pkgs.brightnessctl}/bin/brightnessctl -s s 10%";
          on-resume = "${pkgs.brightnessctl}/bin/brightnessctl -r";
        }
        {
          timeout = 480;
          on-timeout = "pidof hyprlock || hyprlock";
        }
        {
          timeout = 900;
          on-timeout = "niri msg action power-off-monitors 2>/dev/null; hyprctl dispatch dpms off 2>/dev/null; true";
          on-resume = "niri msg action power-on-monitors 2>/dev/null; hyprctl dispatch dpms on 2>/dev/null; true";
        }
      ];
    };
  };

  ########################################
  # yt-dlp
  ########################################
  xdg.configFile."yt-dlp/config".text = ''
    --downloader aria2c
    --downloader-args "aria2c:-x 16 -s 16 -k 1M"
    --concurrent-fragments 5
  '';

  ########################################
  # Packages
  ########################################
  home.packages = with pkgs; [
    # ── Standard CLI / System Utilities ────────────────
    git neovim wget rsync
    jq ripgrep fd bat
    gitleaks unzip resvg
    pythonEnv claude-code
    # rose-pine-cursor  # REMOVED
    bibata-modern-ice   # ADDED
    grim slurp wl-clipboard swappy
    fuzzel cliphist
    ffmpeg mediainfo vlc playerctl libnotify

    # ── GUI Apps ──────────────────────────────────────
    zoom kdePackages.kdenlive
    brave thunderbird libreoffice
    nemo kdePackages.kate krita uniremote ghostty
    librewolf ladybird helium

    # ── Development & Helpers ──────────────────────────
    eza sshfs yt-dlp aria2 imagemagick
    delta lazygit tealdeer nix-your-shell comma helix
    dua mtr sqlite nodejs pavucontrol nvd
    easyeffects nwg-look
    (pkgs.supertux or pkgs.superTux)
    (pkgs.supertuxkart or pkgs.superTuxKart)

    # ── Custom Wrappers / Binaries ─────────────────────
    (writeShellScriptBin "get-theme" ''
      exec ${pythonEnv}/bin/python3 ~/nixos/scripts/auto-theme.py "$@"
    '')

    (writeShellScriptBin "menu" ''
      # Source your dynamic palette
      [ -f "$HOME/.config/waybar/palette.sh" ] && . "$HOME/.config/waybar/palette.sh"

      # Run bemenu with theme-aware colors
      exec bemenu \
        --nb "''${BASE:-#191724}" \
        --nf "''${TEXT:-#e0def4}" \
        --hb "''${HIGHLIGHT_MED:-#403d52}" \
        --hf "''${IRIS:-#c4a7e1}" \
        --tb "''${BASE:-#191724}" \
        --tf "''${LOVE:-#eb6f92}" \
        --fb "''${BASE:-#191724}" \
        --ff "''${FOAM:-#9ccfd8}" \
        --ab "''${BASE:-#191724}" \
        --af "''${TEXT:-#e0def4}" \
        -p "run:" \
        --fn "JetBrainsMono Nerd Font 12" \
        --fork \
        "$@"
    '')
  ];

  # Environment variables to ensure cursor theme is picked up by all apps
  home.sessionVariables = {
    XCURSOR_THEME = "Bibata-Modern-Ice";
    XCURSOR_SIZE = "24";
  };
}
