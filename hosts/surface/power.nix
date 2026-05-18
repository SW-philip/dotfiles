{ pkgs, ... }:

{
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "kernel.nmi_watchdog" = 0;
    "vm.dirty_writeback_centisecs" = 1500;
    "vm.dirty_background_ratio" = 5;
    "vm.dirty_ratio" = 10;
  };

  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=1 power_save_controller=Y
    options snd_sof_intel_hda_common hda_model=dell-headset-multi
  '';

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

  networking.networkmanager.wifi.powersave = true;

  services.power-profiles-daemon.enable = true;
  services.thermald.enable = true;
  services.irqbalance.enable = true;

  powerManagement.enable = true;

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
