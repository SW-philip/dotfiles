{ pkgs, lib, ... }:

{
  ############################################################
  # Services
  ############################################################
  services = {
    fwupd.enable = true;
    deluge = {
      enable = true;
      openFirewall = false;
      web.enable = false;
    };
  };

  ############################################################
  # Smartd (HDD monitoring)
  ############################################################
  services.smartd = {
    enable = true;
    autodetect = false;
    devices = let
      diskOpts = lib.concatStringsSep " " [
        "-a" "-n standby"
        "-s S/../.././02"
        "-s L/../../7/02"
        "-W 4,50,55"
        "-l error" "-l selftest"
      ];
    in [
      { device = "/dev/sda"; options = diskOpts; }
      { device = "/dev/sdb"; options = diskOpts; }
    ];
  };

  ############################################################
  # Packages
  ############################################################
  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];

  ############################################################
  # IPTV m3u HTTP server
  ############################################################
  systemd.services.iptv-serve = {
    description = "IPTV m3u file server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8765 --directory /srv/live";
      Restart = "on-failure";
      RestartSec = "2s";
      User = "prepko";
    };
  };

  systemd.tmpfiles.rules = [
    "z /srv/live  0775 prepko users -"
    "z /srv/tools 0775 prepko users -"
  ];

  ############################################################
  # EPG updater
  ############################################################
  systemd.services.epg-update = {
    description = "Update IPTV EPG from epgshare01";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "prepko";
      UMask = "0133";
      ExecStart = let
        script = pkgs.writeShellScript "epg-update" ''
          set -euo pipefail
          base="https://epgshare01.online/epgshare01"
          fetch() { ${pkgs.curl}/bin/curl -fsSL -A "Mozilla/5.0" "$1" | ${pkgs.gzip}/bin/gunzip; }

          # Use -p /srv/live so temp files stay on the same filesystem as the
          # destination — mv then becomes an atomic rename instead of a
          # cross-device copy, and prepko can write there after the tmpfiles rule.
          us2=$(mktemp -p /srv/live)
          locals=$(mktemp -p /srv/live)
          sports=$(mktemp -p /srv/live)
          trap 'rm -f "$us2" "$locals" "$sports"' EXIT

          fetch "$base/epg_ripper_US2.xml.gz"        > "$us2"
          fetch "$base/epg_ripper_US_LOCALS1.xml.gz" > "$locals"
          fetch "$base/epg_ripper_US_SPORTS1.xml.gz" > "$sports"

          tmp=$(mktemp -p /srv/live)
          {
            grep -v '</tv>' "$us2"
            grep -v '<?xml\|<tv ' "$locals" | grep -v '</tv>'
            grep -v '<?xml\|<tv ' "$sports" | grep -v '</tv>'
            echo '</tv>'
          } > "$tmp"
          mv "$tmp" /srv/live/epg.xml
        '';
      in "${script}";
    };
  };

  systemd.timers.epg-update = {
    description = "Daily EPG update timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };

  ############################################################
  # M3U playlist updater
  ############################################################
  systemd.services.iptv-update = {
    description = "Refresh IPTV M3U playlist from iptv-org tvpass";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "prepko";
      UMask = "0133";
      ExecStart = let
        script = pkgs.writeShellScript "iptv-update" ''
          set -euo pipefail
          LIVE=/srv/live
          # iptv-org merged all sources into one index; no more per-source URLs
          INDEX_URL="https://iptv-org.github.io/iptv/index.m3u"
          FILTER=/srv/tools/filter_m3u.py

          log() { echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $*" | ${pkgs.coreutils}/bin/tee -a "$LIVE/update_iptv.log"; }

          log "=== Starting M3U update ==="

          index=$(mktemp -p "$LIVE" index.XXXXXX.m3u)
          tvpass=$(mktemp -p "$LIVE" tvpass.XXXXXX.m3u)
          out=$(mktemp -p "$LIVE" my_tv.XXXXXX.m3u)
          trap 'rm -f "$index" "$tvpass" "$out"' EXIT

          log "Fetching iptv-org index..."
          ${pkgs.curl}/bin/curl -fsSL -A "Mozilla/5.0" "$INDEX_URL" -o "$index"

          total=$(${pkgs.gnugrep}/bin/grep -c "^#EXTINF" "$index" || true)
          log "Index has $total entries total. Filtering for tvpass..."

          # Extract only tvpass.org entries to avoid name collisions with other providers
          ${pkgs.python3}/bin/python3 - "$index" "$tvpass" <<'EOF'
import sys
lines = open(sys.argv[1]).readlines()
out = ["#EXTM3U\n"]
i = 0
while i < len(lines):
    if lines[i].startswith("#EXTINF"):
        j = i + 1
        while j < len(lines) and lines[j].startswith("#"):
            j += 1
        if j < len(lines) and "tvpass.org" in lines[j]:
            out.extend(lines[i:j+1])
        i = j + 1
    else:
        i += 1
open(sys.argv[2], "w").writelines(out)
EOF

          count=$(${pkgs.gnugrep}/bin/grep -c "^#EXTINF" "$tvpass" || true)
          log "Extracted $count tvpass entries. Running filter_m3u.py..."

          ${pkgs.python3}/bin/python3 "$FILTER" "$tvpass" "$out" 2>>"$LIVE/update_iptv.log"

          mv "$out" "$LIVE/my_tv.m3u"
          log "Updated my_tv.m3u. Done."
        '';
      in "${script}";
    };
  };

  systemd.timers.iptv-update = {
    description = "Daily M3U playlist update (runs after EPG)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 01:30:00";
      Persistent = true;
    };
  };

  ############################################################
  # CPU power management
  ############################################################
  powerManagement.cpuFreqGovernor = "powersave";

  ############################################################
  # Firewall
  ############################################################
  networking.firewall.allowedTCPPorts = [ 8096 8080 8765 ];

}
