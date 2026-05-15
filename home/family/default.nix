{ pkgs, lib, ... }:
{
  imports = [
    ./waybar.nix
    ../mako
  ];

  home.stateVersion = "25.11";
  home.username = "family";
  home.homeDirectory = "/home/family";

  home.activation.niriCfg = lib.hm.dag.entryAfter ["writeBoundary"] (
  let
    palette = import ../../themes/Rose-Pine/main/palette-main.nix;
    layoutSettings = {
      gap = 10;      # Used by l.gap in your template
      borderW = 2;   # Used by l.borderW in your template
    };

    niriConfig = pkgs.writeText "niri-config.kdl" (import ../niri/config.kdl.nix {
      p = palette;
      l = layoutSettings; # <--- This satisfies the 'l' argument
      barHeight = 64;
    });
  in
  ''
    mkdir -p "$HOME/.config/niri"
    cp --remove-destination "${niriConfig}" "$HOME/.config/niri/config.kdl"
    chmod 644 "$HOME/.config/niri/config.kdl"
  '');

  home.file.".Xresources".text = ''
    Xft.dpi: 288
  '';

  home.activation.niriXresources = lib.hm.dag.entryAfter ["niriCfg"] ''
    echo 'spawn-at-startup "xrdb" "-merge" "$HOME/.Xresources"' \
      >> "$HOME/.config/niri/config.kdl"
  '';

  ############################################################
  # Packages
  ############################################################
  home.packages = with pkgs; [
    claude-code
    ghostty
    git
    btop
    fastfetch
    sqlch
    wofi
    fuzzel

    # zsh toolchain
    eza bat fd delta lazygit nix-your-shell
    fzf zoxide ripgrep tealdeer

    # ── Educational: KDE Edu suite ──────────────────────────
    kdePackages.blinken      # Simon-says memory game
    kdePackages.kalzium      # periodic table / chemistry
    kdePackages.kanagram     # anagram word puzzles
    kdePackages.kbruch       # fractions practice
    kdePackages.kgeography   # geography quiz
    kdePackages.khangman     # hangman vocabulary
    kdePackages.ktouch       # typing tutor
    kdePackages.kturtle      # Logo-style programming for kids
    kdePackages.kwordquiz    # flashcard / vocabulary trainer
    kdePackages.marble       # virtual globe / map explorer
    kdePackages.minuet       # music education
    kdePackages.parley       # vocabulary trainer

    # ── Educational: general ────────────────────────────────
    gcompris                 # activities for ages 2–10
    tuxpaint                 # drawing for young kids
    anki                     # flashcard / spaced-repetition learning
    stellarium               # planetarium / astronomy
    kstars                   # KDE desktop planetarium + observatory tools
    celestia                 # 3D space exploration

    # ── Games: strategy / simulation ────────────────────────
    wesnoth                  # turn-based fantasy strategy
    freeciv_qt               # open-source Civilization (Qt client)
    openttd                  # transport management / city building
    lincity-ng               # city-building simulation
    zeroad                   # 0 A.D. historical real-time strategy
    endless-sky              # space trading / exploration

    # ── Games: platformer / action ──────────────────────────
    superTux                 # classic 2D platformer
    superTuxKart             # kart racing
    extremetuxracer          # downhill sledding racer
    pingus                   # Lemmings-style puzzle game
    classicube               # Minecraft-style sandbox (no account needed)
  ];

  xdg.desktopEntries.steam = {
    name     = "Steam";
    exec     = "env STEAM_FORCE_DESKTOPUI_SCALING=2 LIBVA_DRIVER_NAME=iHD steam -no-cef-sandbox %U";
    icon     = "steam";
    terminal = false;
    type     = "Application";
    categories = [ "Network" "FileTransfer" "Game" ];
    mimeType   = [ "x-scheme-handler/steam" "x-scheme-handler/steamlink" ];
    actions = {
      "Store"      = { name = "Store";       exec = "steam steam://store"; };
      "Community"  = { name = "Community";   exec = "steam steam://url/CommunityHome/"; };
      "Library"    = { name = "Library";     exec = "steam steam://open/games"; };
      "BigPicture" = { name = "Big Picture"; exec = "steam steam://open/bigpicture"; };
      "Friends"    = { name = "Friends";     exec = "steam steam://open/friends"; };
      "Settings"   = { name = "Settings";   exec = "steam steam://open/settings"; };
    };
  };

  ############################################################
  # Git
  ############################################################
  programs.git = {
    enable = true;
    settings.user.name  = "family";
    settings.user.email = "";   # set on the machine: git config --global user.email "..."
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size                  = 50000;
      save                  = 50000;
      extended              = true;
      ignoreDups            = true;
      ignoreAllDups         = true;
      expireDuplicatesFirst = true;
      share                 = true;
    };

    shellAliases = {
      ls  = "eza --icons=auto --group-directories-first";
      ll  = "eza -lh --icons=auto --group-directories-first --git";
      la  = "eza -lah --icons=auto --group-directories-first --git";
      lt  = "eza --tree --icons=auto --level=2";
      ltt = "eza --tree --icons=auto";
      cat = "bat --style=plain --paging=never";
      lg  = "lazygit";
      gds = "git diff --staged";
      nrs = "sudo nixos-rebuild switch --flake";
      nrb = "sudo nixos-rebuild boot --flake";
      nrt = "sudo nixos-rebuild test --flake";
      nfu = "nix flake update";
      ".."   = "cd ..";
      "..."  = "cd ../..";
      "...." = "cd ../../..";
      grep = "grep --color=auto";
      ip   = "ip --color=auto";
      diff = "delta";
      lb   = "sudo rm -f /boot/EFI/systemd/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI && sudo rm -f /boot/EFI/Linux/nixos-*.efi";
    };

    oh-my-zsh = {
      enable  = true;
      plugins = [ "git" "sudo" "fzf" "zoxide" "extract" "copypath" "copyfile" ];
    };

    plugins = [
      {
        name = "powerlevel10k";
        src  = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "you-should-use";
        src  = pkgs.zsh-you-should-use;
        file = "share/zsh/plugins/you-should-use/you-should-use.plugin.zsh";
      }
      {
        name = "autopair";
        src  = pkgs.zsh-autopair;
        file = "share/zsh/zsh-autopair/autopair.zsh";
      }
    ];

    initContent = ''
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
      [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
      [ -f "$HOME/.config/sqlch/env" ] && source "$HOME/.config/sqlch/env"

      _set_highlight_styles() {
        ZSH_HIGHLIGHT_STYLES[comment]='fg=#6e6a86'
      }
      add-zsh-hook precmd _set_highlight_styles

      ${pkgs.nix-your-shell}/bin/nix-your-shell zsh | source /dev/stdin

      export MANPAGER="sh -c 'col -bx | bat -l man -p'"
      export MANROFFOPT="-c"

      export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
      export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
      export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
      export FZF_DEFAULT_OPTS='
        --height=50% --layout=reverse --border=rounded
        --info=inline --cycle
        --bind=ctrl-u:preview-page-up,ctrl-d:preview-page-down
        --bind=ctrl-/:toggle-preview
        --color=base:#232136,bg+:#2a2837,fg:#e0def4,fg+:#e0def4
        --color=hl:#eb6f92,hl+:#eb6f92,info:#9ccfd8,prompt:#c4a7e7
        --color=pointer:#eb6f92,marker:#f6c177,spinner:#9ccfd8,header:#6e6a86
        --color=border:#44415a,gutter:#232136
      '
      export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {}'"
      export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always --icons {} 2>/dev/null | head -100'"

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

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      style                            = "compact";
      search_mode                      = "fuzzy";
      filter_mode_shell_up_key_binding = "session";
      show_preview                     = true;
      inline_height                    = 20;
    };
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

}
