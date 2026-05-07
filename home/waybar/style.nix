# Waybar dark theme CSS — generated from palette.nix
# Derived tinted hover backgrounds (thermal gradient) are kept as literal hex;
# everything else references palette variables.
{ p, l }:
let
  tooltipBg = if p ? OVERLAY_RGB then "rgba(${p.OVERLAY_RGB},0.99)" else p.WB_BASE;
in
''
/* ============================================================
 * WAYBAR — DARK THEME
 * GTK-compatible (no CSS custom properties)
 * At rest: neutral. On hover: full color reveal.
 * ============================================================ */

window#waybar {
  background: transparent;
  font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", "Maple Mono", "Noto Sans Mono", monospace;
  font-size: ${p.FONT_SIZE_BAR};
  color: ${p.TEXT};
}

/* -----------------------------------------------------------------
   Generic module
   ----------------------------------------------------------------- */
.module {
  background: ${p.WB_SURFACE};
  color: ${p.TEXT};
  text-shadow: ${p.ICON_SHADOW};
  padding: 4px 14px;
  margin: 5px 3px;
  border-radius: ${toString l.radiusMd}px;
  border: 1px solid rgba(${p.BORDER_ACCENT_RGB},0.18);
  border-top-color: rgba(255,255,255,${p.BORDER_TOP_A});
  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 -1px 0 rgba(${p.SHADOW_RGB},${p.INSET_BOT_A}) inset,
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 2px 8px rgba(${p.BORDER_ACCENT_RGB},0.10),
    0 4px ${toString l.shadowBlur}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});
  transition:
    background 0.15s ease,
    color 0.15s ease,
    border-color 0.15s ease,
    box-shadow 0.15s ease;
}

.module:hover {
  background: ${p.WB_OVERLAY};
  color: ${p.TEXT};
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.30);
  border-top-color: rgba(255,255,255,${p.BORDER_TOP_A});
  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 -1px 0 rgba(${p.SHADOW_RGB},${p.INSET_BOT_A}) inset,
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 4px ${toString (l.shadowBlur + 4)}px ${toString l.shadowSpread}px rgba(${p.BORDER_ACCENT_RGB},0.20),
    0 5px ${toString (l.shadowBlur + 2)}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER});
}

/* -----------------------------------------------------------------
   Elevation tiers (resting backgrounds only)
   ----------------------------------------------------------------- */
#custom-clock,
#custom-battery {
  background: ${p.WB_OVERLAY};
  border-color: rgba(${p.BORDER_IRIS_RGB},0.14);
}

#custom-weather,
#custom-cpu_temp,
#custom-volume,
#custom-mpris {
  background: ${p.WB_SURFACE};
}

#custom-network,
#custom-bluetooth,
#tray {
  background: ${p.WB_BASE};
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.08);
}

/* -----------------------------------------------------------------
   Start button — always lit, NixOS launcher anchor
   ----------------------------------------------------------------- */
#custom-start {
  color: ${p.IRIS};
  background: linear-gradient(180deg, ${p.WB_OVERLAY} 0%, ${p.OVERLAY} 100%);
  border-color: rgba(${p.BORDER_IRIS_RGB},0.35);
  font-weight: 600;
  letter-spacing: 0.04em;
  padding-left: 16px;
  padding-right: 16px;
}
#custom-start:hover {
  color: ${p.TEXT};
  background: ${p.OVERLAY};
  border-color: rgba(${p.BORDER_IRIS_RGB},0.55);
  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 3px 10px rgba(${p.BORDER_IRIS_RGB},0.20),
    0 3px 8px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER});
}

/* -----------------------------------------------------------------
   Clock — always lit, it's the anchor
   ----------------------------------------------------------------- */
#custom-clock          { font-weight: 600; letter-spacing: 0.05em; color: ${p.TEXT}; }
#custom-clock:hover    { color: ${p.TEXT}; background: ${p.OVERLAY}; border-color: rgba(${p.BORDER_ACCENT_RGB},0.25); box-shadow: 0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset, 0 3px 10px rgba(${p.BORDER_ACCENT_RGB},0.15), 0 3px 8px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER}); }

/* -----------------------------------------------------------------
   Weather
   ----------------------------------------------------------------- */
#custom-weather        { color: ${p.MUTED_ICON}; }
#custom-weather:hover  { color: ${p.TEXT}; background: ${p.OVERLAY}; border-color: rgba(${p.BORDER_ACCENT_RGB},0.25); box-shadow: 0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset, 0 3px 10px rgba(${p.BORDER_ACCENT_RGB},0.15), 0 3px 8px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER}); }

/* -----------------------------------------------------------------
   CPU temperature — neutral at rest, thermal scale on hover
   ----------------------------------------------------------------- */
#custom-cpu_temp               { color: ${p.MUTED_ICON}; }
#custom-cpu_temp.cool:hover     { color: ${p.FOAM}; }
#custom-cpu_temp.warm:hover     { color: ${p.CAUTION}; }
#custom-cpu_temp.hot:hover      { color: ${p.WARNING}; }
#custom-cpu_temp.critical:hover { color: ${p.CRITICAL}; }

/* -----------------------------------------------------------------
   Battery — neutral at rest, cool→warm reveal on hover
   ----------------------------------------------------------------- */
#custom-battery                { color: ${p.MUTED_ICON}; }
#custom-battery.full:hover     { color: ${p.FOAM}; }
#custom-battery.high:hover     { color: #7ab3c0; }
#custom-battery.medium:hover   { color: #a0d44e; }
#custom-battery.low:hover      { color: ${p.WARNING}; }
#custom-battery.critical:hover { color: ${p.CRITICAL}; }

/* -----------------------------------------------------------------
   Volume — neutral at rest, thermal gradient on hover
   ----------------------------------------------------------------- */
#custom-volume         { color: ${p.MUTED_ICON}; }
#custom-volume.muted   { color: ${p.MUTED}; }

#custom-volume.muted:hover,
#custom-volume.vol-0:hover   { background: ${p.HOVER_MUTED_BG}; color: ${p.MUTED}; }
#custom-volume.vol-5:hover   { background: ${p.HOVER_TEAL_BG}; color: #6e9aa8; }
#custom-volume.vol-10:hover  { background: ${p.HOVER_TEAL_BG}; color: #7ab3c0; }
#custom-volume.vol-15:hover  { background: ${p.HOVER_TEAL_BG}; color: #8ac8d4; }
#custom-volume.vol-20:hover  { background: ${p.TINT_PINE_MID}; color: ${p.FOAM}; }
#custom-volume.vol-25:hover  { background: ${p.TINT_PINE_MID}; color: ${p.FOAM}; }
#custom-volume.vol-30:hover  { background: ${p.TINT_PINE_DARK}; color: ${p.FOAM}; }
#custom-volume.vol-35:hover  { background: ${p.HOVER_GREEN_BG}; color: #7ecba8; }
#custom-volume.vol-40:hover  { background: ${p.HOVER_GREEN_BG}; color: #6dc99a; }
#custom-volume.vol-45:hover  { background: ${p.HOVER_GREEN_BG}; color: #5ec88c; }
#custom-volume.vol-50:hover  { background: ${p.HOVER_GREEN_BG}; color: #72cc6a; }
#custom-volume.vol-55:hover  { background: ${p.HOVER_GREEN_BG}; color: #a0d44e; }
#custom-volume.vol-60:hover  { background: ${p.HOVER_GOLD_BG}; color: ${p.CAUTION}; }
#custom-volume.vol-65:hover  { background: ${p.HOVER_GOLD_BG}; color: #ddd028; }
#custom-volume.vol-70:hover  { background: ${p.HOVER_ORANGE_BG}; color: #f0c020; }
#custom-volume.vol-75:hover  { background: ${p.HOVER_ORANGE_BG}; color: ${p.GOLD}; }
#custom-volume.vol-80:hover  { background: ${p.TINT_CRITICAL_BG}; color: #d94f3a; }
#custom-volume.vol-85:hover  { background: ${p.TINT_CRITICAL_BG}; color: #c0302a; }
#custom-volume.vol-90:hover  { background: ${p.TINT_CRITICAL_BG}; color: #b82020; }
#custom-volume.vol-95:hover  { background: ${p.TINT_CRITICAL_BG}; color: #e0306a; }
#custom-volume.vol-100:hover { background: ${p.TINT_CRITICAL_BG}; color: ${p.CRITICAL}; border-color: rgba(240,64,160,0.4); }

/* -----------------------------------------------------------------
   Media player — dim at rest, status color on hover
   ----------------------------------------------------------------- */
#custom-mpris              { color: ${p.MUTED_ICON}; }
#custom-mpris.playing      { color: ${p.FOAM}; }
#custom-mpris.paused       { color: ${p.SUBTLE}; }
#custom-mpris.stopped      { opacity: 0.45; }
#custom-mpris:hover        { color: ${p.TEXT}; background: ${p.OVERLAY}; border-color: rgba(${p.BORDER_ACCENT_RGB},0.25); box-shadow: 0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset, 0 3px 10px rgba(${p.BORDER_ACCENT_RGB},0.15), 0 3px 8px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER}); }

/* -----------------------------------------------------------------
   sqlch radio — status tint at rest
   ----------------------------------------------------------------- */
#custom-sqlch              { color: ${p.MUTED_ICON}; }
#custom-sqlch.playing      { color: ${p.FOAM}; }
#custom-sqlch.paused       { color: ${p.SUBTLE}; }
#custom-sqlch.idle         { color: ${p.MUTED}; opacity: 0.6; }
#custom-sqlch.inactive     { opacity: 0.35; }
#custom-sqlch:hover        { color: ${p.TEXT}; background: ${p.OVERLAY}; border-color: rgba(${p.BORDER_ACCENT_RGB},0.25); box-shadow: 0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset, 0 3px 10px rgba(${p.BORDER_ACCENT_RGB},0.15), 0 3px 8px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER}); }

/* -----------------------------------------------------------------
   Network — dim at rest, signal-strength color on hover
   ----------------------------------------------------------------- */
#custom-network                    { color: ${p.MUTED_ICON}; }
#custom-network.wifi.low:hover     { color: ${p.WARNING}; }
#custom-network.wifi.mid:hover     { color: ${p.CAUTION}; }
#custom-network.wifi.high:hover    { color: #7ab3c0; }
#custom-network.wifi.full:hover    { color: ${p.FOAM}; }
#custom-network.wired:hover        { color: ${p.FOAM}; }
#custom-network.vpn:hover          { color: ${p.IRIS}; }
#custom-network.offline            { opacity: 0.45; }
#custom-network.offline:hover      { opacity: 0.7; color: ${p.MUTED}; }

/* -----------------------------------------------------------------
   Bluetooth — dim at rest, state color on hover
   ----------------------------------------------------------------- */
#custom-bluetooth      { color: ${p.MUTED_ICON}; }
#custom-bluetooth.off  { opacity: 0.45; }
#custom-bluetooth:hover { color: ${p.TEXT}; }

/* -----------------------------------------------------------------
   btrfs storage — neutral at rest, usage scale on hover
   ----------------------------------------------------------------- */
#custom-btrfs                  { color: ${p.MUTED_ICON}; }
#custom-btrfs.fresh:hover      { color: ${p.FOAM}; }
#custom-btrfs.ok:hover         { color: ${p.CAUTION}; }
#custom-btrfs.warn:hover       { color: ${p.WARNING}; }
#custom-btrfs.critical:hover   { color: ${p.CRITICAL}; }

/* -----------------------------------------------------------------
   Flake drift — neutral at rest, freshness scale on hover
   ----------------------------------------------------------------- */
#custom-flake-drift              { color: ${p.MUTED_ICON}; }
#custom-flake-drift.fresh:hover  { color: ${p.FOAM}; }
#custom-flake-drift.ok:hover     { color: ${p.CAUTION}; }
#custom-flake-drift.aging:hover  { color: ${p.WARNING}; }
#custom-flake-drift.stale:hover  { color: ${p.CRITICAL}; }

/* -----------------------------------------------------------------
   CPU/RAM performance — neutral at rest, usage scale on hover
   ----------------------------------------------------------------- */
#custom-perf                   { color: ${p.MUTED_ICON}; }
#custom-perf.idle:hover        { color: ${p.FOAM}; }
#custom-perf.active:hover      { color: ${p.CAUTION}; }
#custom-perf.warn:hover        { color: ${p.WARNING}; }
#custom-perf.critical:hover    { color: ${p.CRITICAL}; }

/* -----------------------------------------------------------------
   Power profile — state color at rest, full reveal on hover
   ----------------------------------------------------------------- */
#custom-power_profile                  { color: ${p.MUTED_ICON}; }
#custom-power_profile.power-saver      { color: ${p.FOAM}; }
#custom-power_profile.performance      { color: ${p.LOVE}; }
#custom-power_profile:hover            { color: ${p.TEXT}; }

/* -----------------------------------------------------------------
   Idle inhibit toggle — state color at rest
   ----------------------------------------------------------------- */
#custom-idle_inhibit           { color: ${p.MUTED_ICON}; }
#custom-idle_inhibit.active    { color: ${p.FOAM}; }
#custom-idle_inhibit.inhibited { color: ${p.MUTED}; opacity: 0.6; }
#custom-idle_inhibit:hover     { color: ${p.TEXT}; opacity: 1; }

/* -----------------------------------------------------------------
   DND toggle — state color at rest
   ----------------------------------------------------------------- */
#custom-dnd          { color: ${p.MUTED_ICON}; }
#custom-dnd.dnd      { color: ${p.GOLD}; }
#custom-dnd:hover    { color: ${p.TEXT}; }

/* -----------------------------------------------------------------
   Utilities handle + choose_mode — dim at rest, reveal on hover
   ----------------------------------------------------------------- */
#custom-utilities-handle       { color: ${p.MUTED}; }
#custom-utilities-handle:hover { color: ${p.MUTED_ICON}; }
#custom-choose_mode            { color: ${p.MUTED_ICON}; }
#custom-choose_mode:hover      { color: ${p.TEXT}; }

/* -----------------------------------------------------------------
   Wleave (power menu) — dim at rest, LOVE on hover
   ----------------------------------------------------------------- */
#custom-wleave       { color: ${p.MUTED_ICON}; }
#custom-wleave:hover { color: ${p.LOVE}; }

/* -----------------------------------------------------------------
   Uniremote launcher — dim at rest, reveal on hover
   ----------------------------------------------------------------- */
#custom-uniremote       { color: ${p.MUTED_ICON}; }
#custom-uniremote:hover { color: ${p.TEXT}; }

/* -----------------------------------------------------------------
   Toggles group — single pill, inner modules lose individual borders
   ----------------------------------------------------------------- */
#toggles {
  background: ${p.WB_BASE};
  border: 1px solid rgba(${p.BORDER_ACCENT_RGB},0.08);
  border-radius: ${toString l.radiusLg}px;
  margin: 5px 3px;
  padding: 0;

  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 -1px 0 rgba(${p.SHADOW_RGB},${p.INSET_BOT_A}) inset,
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 2px 8px rgba(${p.BORDER_ACCENT_RGB},0.10),
    0 4px ${toString l.shadowBlur}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});
  transition: background 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease;
}

#toggles:hover {
  background: ${p.WB_OVERLAY};
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.30);
  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 -1px 0 rgba(${p.SHADOW_RGB},${p.INSET_BOT_A}) inset,
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 4px ${toString (l.shadowBlur + 4)}px ${toString l.shadowSpread}px rgba(${p.BORDER_ACCENT_RGB},0.20),
    0 5px ${toString (l.shadowBlur + 2)}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER});
}

/* shared chip hover for all group pill interiors */
#toggles > widget > *,
#connectivity > widget > *,
#actions > widget > *,
#system-stats > widget > *,
#storage > widget > * {
  background: rgba(255,255,255,0.04);
  border: none;
  border-radius: ${toString (l.radiusLg - 2)}px;
  margin: 0 1px;
  box-shadow: none;
  padding: 4px 10px;
  transition: background 0.12s ease, color 0.12s ease;
}

#toggles > widget > *:hover,
#connectivity > widget > *:hover,
#actions > widget > *:hover,
#system-stats > widget > *:hover,
#storage > widget > *:hover {
  background: rgba(255,255,255,0.12);
  border-radius: ${toString (l.radiusLg - 2)}px;
  box-shadow: none;
  border: none;
}

#toggles > widget:first-child > *,
#connectivity > widget:first-child > *,
#actions > widget:first-child > *,
#system-stats > widget:first-child > *,
#storage > widget:first-child > * { padding-left: 12px; }

#toggles > widget:last-child > *,
#connectivity > widget:last-child > *,
#actions > widget:last-child > *,
#system-stats > widget:last-child > *,
#storage > widget:last-child > *  { padding-right: 12px; }

/* -----------------------------------------------------------------
   Connectivity group (bluetooth + network) — shared pill
   ----------------------------------------------------------------- */
#connectivity {
  background: ${p.WB_BASE};
  border: 1px solid rgba(${p.BORDER_ACCENT_RGB},0.08);
  border-radius: ${toString l.radiusLg}px;
  margin: 5px 3px;
  padding: 0;

  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 -1px 0 rgba(${p.SHADOW_RGB},${p.INSET_BOT_A}) inset,
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 2px 8px rgba(${p.BORDER_ACCENT_RGB},0.10),
    0 4px ${toString l.shadowBlur}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});
  transition: background 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease;
}

#connectivity:hover {
  background: ${p.WB_OVERLAY};
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.30);
  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 -1px 0 rgba(${p.SHADOW_RGB},${p.INSET_BOT_A}) inset,
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 4px ${toString (l.shadowBlur + 4)}px ${toString l.shadowSpread}px rgba(${p.BORDER_ACCENT_RGB},0.20),
    0 5px ${toString (l.shadowBlur + 2)}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER});
}


/* -----------------------------------------------------------------
   Actions group (uniremote + wleave) — shared pill
   ----------------------------------------------------------------- */
#actions {
  background: ${p.WB_BASE};
  border: 1px solid rgba(${p.BORDER_ACCENT_RGB},0.08);
  border-radius: ${toString l.radiusLg}px;
  margin: 5px 3px;
  padding: 0;

  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 -1px 0 rgba(${p.SHADOW_RGB},${p.INSET_BOT_A}) inset,
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 2px 8px rgba(${p.BORDER_ACCENT_RGB},0.10),
    0 4px ${toString l.shadowBlur}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});
  transition: background 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease;
}

#actions:hover {
  background: ${p.WB_OVERLAY};
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.30);
  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 -1px 0 rgba(${p.SHADOW_RGB},${p.INSET_BOT_A}) inset,
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 4px ${toString (l.shadowBlur + 4)}px ${toString l.shadowSpread}px rgba(${p.BORDER_ACCENT_RGB},0.20),
    0 5px ${toString (l.shadowBlur + 2)}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER});
}


/* -----------------------------------------------------------------
   System-stats group (battery + cpu_temp) — shared pill
   ----------------------------------------------------------------- */
#system-stats {
  background: ${p.WB_OVERLAY};
  border: 1px solid rgba(${p.BORDER_IRIS_RGB},0.14);
  border-radius: ${toString l.radiusLg}px;
  margin: 5px 3px;
  padding: 0;

  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 -1px 0 rgba(${p.SHADOW_RGB},${p.INSET_BOT_A}) inset,
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 2px 8px rgba(${p.BORDER_ACCENT_RGB},0.10),
    0 4px ${toString l.shadowBlur}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});
  transition: background 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease;
}

#system-stats:hover {
  background: ${p.OVERLAY};
  border-color: rgba(${p.BORDER_IRIS_RGB},0.28);
  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 -1px 0 rgba(${p.SHADOW_RGB},${p.INSET_BOT_A}) inset,
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 4px ${toString (l.shadowBlur + 4)}px ${toString l.shadowSpread}px rgba(${p.BORDER_ACCENT_RGB},0.20),
    0 5px ${toString (l.shadowBlur + 2)}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER});
}


/* -----------------------------------------------------------------
   Storage group (btrfs + flake-drift) — shared pill
   ----------------------------------------------------------------- */
#storage {
  background: ${p.WB_BASE};
  border: 1px solid rgba(${p.BORDER_ACCENT_RGB},0.08);
  border-radius: ${toString l.radiusLg}px;
  margin: 5px 3px;
  padding: 0;

  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 -1px 0 rgba(${p.SHADOW_RGB},${p.INSET_BOT_A}) inset,
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 2px 8px rgba(${p.BORDER_ACCENT_RGB},0.10),
    0 4px ${toString l.shadowBlur}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});
  transition: background 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease;
}

#storage:hover {
  background: ${p.WB_OVERLAY};
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.30);
  box-shadow:
    0 1px 0 rgba(255,255,255,${p.INSET_TOP_A}) inset,
    0 -1px 0 rgba(${p.SHADOW_RGB},${p.INSET_BOT_A}) inset,
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 4px ${toString (l.shadowBlur + 4)}px ${toString l.shadowSpread}px rgba(${p.BORDER_ACCENT_RGB},0.20),
    0 5px ${toString (l.shadowBlur + 2)}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_HOVER});
}


/* -----------------------------------------------------------------
   Workspaces — inactive dim, active always lit
   ----------------------------------------------------------------- */
#workspaces button {
  background: transparent;
  color: ${p.MUTED};
  padding: 0 7px;
  margin: 0 1px;
  border-radius: ${toString l.radiusSm}px;
  border: 1px solid transparent;
  transition: background 0.1s ease, color 0.1s ease;
}

#workspaces button.active {
  background: ${p.OVERLAY};
  color: ${p.TEXT};
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.35);
  box-shadow: 0 0 8px rgba(${p.BORDER_ACCENT_RGB},0.2);
}

#workspaces button:hover {
  background: ${p.GRAD_BASE_HI};
  color: ${p.MUTED_ICON};
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.18);
}

/* -----------------------------------------------------------------
   Tray
   ----------------------------------------------------------------- */
#tray > .passive          { -gtk-icon-effect: dim; }
#tray > .needs-attention  { -gtk-icon-effect: highlight; }

/* -----------------------------------------------------------------
   Tooltips
   ----------------------------------------------------------------- */

/* Make the outer GTK window node transparent so border-radius
   corners aren't filled by GTK's own background paint. */
window.background.tooltip {
  background-color: transparent;
  border-radius: ${toString l.radiusMd}px;
}

tooltip {
  background: ${tooltipBg};
  border: 1px solid ${p.HIGHLIGHT_MED};
  border-radius: ${toString l.radiusMd}px;
  padding: 4px 2px;
  box-shadow:
    0 0 0 1px rgba(${p.SHADOW_RGB},${p.SHADOW_A_OUTER}),
    0 4px ${toString l.shadowBlur}px ${toString l.shadowSpread}px rgba(${p.SHADOW_RGB},${p.SHADOW_A_DROP});
}

tooltip label {
  color: ${p.TEXT};
  font-size: 13px;
  font-weight: 600;
  padding: 3px 10px;
}
''
