{ config, pkgs, lib, ... }:
{
  imports = [ ../cachix.nix ];

  options.myConfig.user = lib.mkOption {
    type        = lib.types.str;
    default     = "prepko";
    description = "Primary user account name, used wherever a literal username is needed.";
  };

  config = {
  ############################################################
  # Documentation
  ############################################################
  documentation.doc.enable = false;

  ############################################################
  # Identity / Locale
  ############################################################
  time.timeZone = "America/New_York";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings.LC_ALL = "en_US.UTF-8";
    inputMethod.enable = false;
  };

  ############################################################
  # Users
  ############################################################
  users.users.prepko = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "input"
      "plugdev"
      "i2c"
      "bluetooth"
      "lp"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINPtATBEnWGdS8elZNutgVK1KgspVa2bEtuDm4xCKMgF phil@desktop"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/yWCftiHSN3nAh0v4s/d8QY3xz0+6iqdY3W0Vy7wrs surface"
    ];
  };

  ############################################################
  # Shell
  ############################################################
  programs.zsh.enable = true;

  ############################################################
  # Networking / SSH
  ############################################################
  networking.networkmanager.enable = true;
  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.services.NetworkManager-dispatcher.enable = false;
  services.openssh = {
    enable = true;
    settings = {
      UseDns = lib.mkForce false;
      GSSAPIAuthentication = false;
      PermitRootLogin = "no";
      PasswordAuthentication = true;
      X11Forwarding = false;
      AllowTcpForwarding = false;
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
    };
  };
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  ############################################################
  # Journal limits
  ############################################################
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    RuntimeMaxUse=64M
    MaxFileSec=1month
  '';



  ############################################################
  # Base system packages
  ############################################################
  environment.systemPackages = with pkgs; [
    curl
    pciutils
    usbutils
    sbctl
    sysstat
    lm_sensors
    brightnessctl
    bemenu
    smartmontools

    btrfs-progs      # btrfs maintenance (balance, scrub, subvolume ops)
    cryptsetup       # LUKS runtime management / recovery
    nvme-cli         # NVMe diagnostics

    tpm2-tools       # TPM2 diagnostics (used in boot, needed in userspace)
    efibootmgr       # EFI boot entry management (lanzaboote debugging)

    age
    sops

    iotop            # Disk I/O monitoring
    lsof             # List open files

    iputils          # ping, tracepath, etc.
    iw               # nl80211 wireless configuration / debugging
  ];

  ############################################################
  # Fonts
  ############################################################
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    nerd-fonts.hack
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    eb-garamond
  ];

  ############################################################
  # Wayland session environment
  ############################################################
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    GDK_BACKEND    = "wayland,x11";
    GTK_USE_PORTAL = "1";
    GDK_SCALE      = "1";
    GDK_DPI_SCALE  = "1";
  };

  ############################################################
  # GTK / GI introspection
  ############################################################
  environment.sessionVariables.GI_TYPELIB_PATH =
    lib.makeSearchPath "lib/girepository-1.0" [
      pkgs.glib.out
      pkgs.gobject-introspection.out
      pkgs.atk.out
      pkgs.pango.out
      pkgs.gdk-pixbuf.out
      pkgs.gtk3.out
    ];

  ############################################################
  # Nix hygiene
  ############################################################
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    http-connections = 25;
    connect-timeout = 10;
    stalled-download-timeout = 90;
    trusted-users = [ config.myConfig.user ];
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
    persistent = true;
  };

  # HM activation already runs at switch-time; skip the redundant boot-time run
  systemd.services."home-manager-${config.myConfig.user}".wantedBy = lib.mkForce [ ];

  hardware.enableRedistributableFirmware = true;
  }; # end config
}
