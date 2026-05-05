{ pkgs, ... }:

{
  # Kernel tuning
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "kernel.nmi_watchdog" = 0;
    "vm.dirty_writeback_centisecs" = 1500;
  };

  # Audio power management
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=1 power_save_controller=Y
    options snd_sof_intel_hda_common hda_model=dell-headset-multi
  '';

  # Runtime PM for all PCI devices
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
    ACTION=="change", SUBSYSTEM=="pci", ATTR{power/control}="auto"
  '';

  systemd.services.pci-runtime-pm = {
    description = "Enable PCI Runtime PM";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      for i in /sys/bus/pci/devices/*/power/control; do
        echo auto > $i
      done
    '';
  };

  # WiFi power saving
  networking.networkmanager.wifi.powersave = true;

  # Power profiles daemon (already running, just making it declarative)
  services.power-profiles-daemon.enable = true;

  # General power management
  powerManagement.enable = true;

  # Sleep drain tracker — records BAT1 energy before/after each sleep cycle.
  # ExecStart fires before sleep (pre), ExecStop fires on wake (post).
  # Signals waybar (SIGRTMIN+2) to refresh the sleep_drain module immediately.
  systemd.services.sleep-drain = {
    description = "Record battery drain across sleep cycles";
    before   = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    serviceConfig = {
      Type              = "oneshot";
      RemainAfterExit   = true;
      ExecStartPre = "+${pkgs.coreutils}/bin/mkdir -p /home/prepko/.cache/sleep-drain";
      ExecStart = pkgs.writeShellScript "sleep-drain-pre" ''
        printf '%s\n%s\n' \
          "$(cat /sys/class/power_supply/BAT1/energy_now 2>/dev/null || echo 0)" \
          "$(${pkgs.coreutils}/bin/date +%s)" \
          > /home/prepko/.cache/sleep-drain/pre
      '';
      ExecStop = pkgs.writeShellScript "sleep-drain-post" ''
        printf '%s\n%s\n' \
          "$(cat /sys/class/power_supply/BAT1/energy_now 2>/dev/null || echo 0)" \
          "$(${pkgs.coreutils}/bin/date +%s)" \
          > /home/prepko/.cache/sleep-drain/post
        ${pkgs.procps}/bin/pkill -u prepko -RTMIN+2 waybar 2>/dev/null || true
      '';
    };
  };
}
