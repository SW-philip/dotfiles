# Ironbar dark theme — palette-aware CSS generated from palette.nix
# Mirror of waybar/style.nix; GTK-compatible (no CSS custom properties).
# At rest: neutral. On hover: full color reveal.
p: ''
/* ============================================================
 * IRONBAR — DARK THEME  (ported from waybar style.nix)
 * GTK-compatible CSS
 * At rest: neutral. On hover: full color reveal.
 * ============================================================ */

window {
  background: transparent;
  background-color: transparent;
}

#bar {
  background: transparent;
  font-family: "JetBrains Mono", "Maple Mono", "Noto Sans Mono", monospace;
  font-size: 12px;
  color: ${p.TEXT};
}

/* -----------------------------------------------------------------
   Generic widget (ironbar's .widget replaces waybar's .module)
   ----------------------------------------------------------------- */
.widget {
  background: linear-gradient(180deg, ${p.GRAD_SURFACE_HI} 0%, ${p.GRAD_SURFACE_LO} 100%);
  color: ${p.TEXT};
  padding: 4px 14px;
  margin: 5px 3px;
  border-radius: 8px;
  border: 1px solid rgba(${p.BORDER_ACCENT_RGB},0.18);
  border-top-color: rgba(255,255,255,0.07);
  box-shadow:
    0 1px 0 rgba(255,255,255,0.08) inset,
    0 -1px 0 rgba(0,0,0,0.30) inset,
    0 0 0 1px rgba(0,0,0,0.50),
    0 2px 8px rgba(${p.BORDER_ACCENT_RGB},0.10),
    0 4px 10px rgba(0,0,0,0.55);
  transition:
    background 0.15s ease,
    color 0.15s ease,
    border-color 0.15s ease,
    box-shadow 0.15s ease;
}

.widget:hover {
  background: linear-gradient(180deg, ${p.GRAD_OVERLAY_HI} 0%, ${p.OVERLAY} 100%);
  color: ${p.TEXT};
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.30);
  border-top-color: rgba(255,255,255,0.07);
  box-shadow:
    0 1px 0 rgba(255,255,255,0.10) inset,
    0 -1px 0 rgba(0,0,0,0.25) inset,
    0 0 0 1px rgba(0,0,0,0.50),
    0 4px 14px rgba(${p.BORDER_ACCENT_RGB},0.20),
    0 5px 12px rgba(0,0,0,0.65);
}

/* -----------------------------------------------------------------
   Elevation tiers (resting backgrounds only)
   ----------------------------------------------------------------- */
#clock,
#battery {
  background: linear-gradient(180deg, ${p.GRAD_OVERLAY_HI} 0%, ${p.GRAD_OVERLAY_LO} 100%);
  border-color: rgba(${p.BORDER_IRIS_RGB},0.20);
}

#weather,
#cpu_temp,
#volume,
#mpris {
  background: linear-gradient(180deg, ${p.GRAD_SURFACE_HI} 0%, ${p.GRAD_SURFACE_LO} 100%);
}

#network,
#bluetooth,
#tray {
  background: linear-gradient(180deg, ${p.GRAD_BASE_HI} 0%, ${p.GRAD_BASE_LO} 100%);
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.12);
}

/* -----------------------------------------------------------------
   Clock — always lit, it's the anchor
   ----------------------------------------------------------------- */
#clock          { font-weight: 600; letter-spacing: 0.05em; color: ${p.TEXT}; }
#clock:hover    { color: ${p.TEXT}; background: ${p.OVERLAY}; border-color: rgba(${p.BORDER_ACCENT_RGB},0.25); box-shadow: 0 1px 0 rgba(255,255,255,0.08) inset, 0 3px 10px rgba(${p.BORDER_ACCENT_RGB},0.15), 0 3px 8px rgba(0,0,0,0.6); }

/* -----------------------------------------------------------------
   Weather
   ----------------------------------------------------------------- */
#weather        { color: ${p.MUTED_ICON}; }
#weather:hover  { color: ${p.TEXT}; background: ${p.OVERLAY}; border-color: rgba(${p.BORDER_ACCENT_RGB},0.25); box-shadow: 0 1px 0 rgba(255,255,255,0.08) inset, 0 3px 10px rgba(${p.BORDER_ACCENT_RGB},0.15), 0 3px 8px rgba(0,0,0,0.6); }

/* -----------------------------------------------------------------
   CPU temperature — neutral at rest, thermal scale on hover
   ----------------------------------------------------------------- */
#cpu_temp               { color: ${p.MUTED_ICON}; }
#cpu_temp.cool:hover    { color: ${p.FOAM}; background: #192830; border-color: rgba(156,207,216,0.15); }
#cpu_temp.warm:hover    { color: ${p.CAUTION}; background: #2a2e12; border-color: rgba(200,219,56,0.18); }
#cpu_temp.hot:hover     { color: ${p.WARNING}; background: #3a2810; border-color: rgba(240,160,32,0.22); }
#cpu_temp.critical:hover { color: ${p.CRITICAL}; background: ${p.TINT_CRITICAL_BG}; border-color: rgba(240,64,160,0.38); }

/* -----------------------------------------------------------------
   Battery — neutral at rest, cool→warm reveal on hover
   ----------------------------------------------------------------- */
#battery                { color: ${p.MUTED_ICON}; }
#battery.full:hover     { color: ${p.FOAM}; background: ${p.TINT_PINE_MID}; border-color: rgba(156,207,216,0.2); }
#battery.high:hover     { color: #7ab3c0; background: #1a2e30; border-color: rgba(122,179,192,0.16); }
#battery.medium:hover   { color: #a0d44e; background: #2c3012; border-color: rgba(160,212,78,0.16); }
#battery.low:hover      { color: ${p.WARNING}; background: #3a200a; border-color: rgba(240,160,32,0.24); }
#battery.critical:hover { color: ${p.CRITICAL}; background: ${p.TINT_CRITICAL_BG}; border-color: rgba(240,64,160,0.38); }

/* -----------------------------------------------------------------
   Volume — neutral at rest, thermal gradient on hover
   ----------------------------------------------------------------- */
#volume         { color: ${p.MUTED_ICON}; }
#volume.muted   { color: ${p.MUTED}; }

#volume.muted:hover,
#volume.vol-0:hover   { background: #1e1e2a; color: ${p.MUTED}; }
#volume.vol-5:hover   { background: #1b2430; color: #6e9aa8; }
#volume.vol-10:hover  { background: #192930; color: #7ab3c0; }
#volume.vol-15:hover  { background: #172e32; color: #8ac8d4; }
#volume.vol-20:hover  { background: ${p.TINT_PINE_MID}; color: ${p.FOAM}; }
#volume.vol-25:hover  { background: #153635; color: ${p.FOAM}; }
#volume.vol-30:hover  { background: ${p.TINT_PINE_DARK}; color: ${p.FOAM}; }
#volume.vol-35:hover  { background: #163d32; color: #7ecba8; }
#volume.vol-40:hover  { background: #173f2d; color: #6dc99a; }
#volume.vol-45:hover  { background: #1a4228; color: #5ec88c; }
#volume.vol-50:hover  { background: #1f4420; color: #72cc6a; }
#volume.vol-55:hover  { background: #2c4418; color: #a0d44e; }
#volume.vol-60:hover  { background: #3a4212; color: ${p.CAUTION}; }
#volume.vol-65:hover  { background: #433b0e; color: #ddd028; }
#volume.vol-70:hover  { background: #4a320c; color: #f0c020; }
#volume.vol-75:hover  { background: #4e280a; color: ${p.GOLD}; }
#volume.vol-80:hover  { background: #4a1a12; color: #d94f3a; }
#volume.vol-85:hover  { background: #481018; color: #c0302a; }
#volume.vol-90:hover  { background: #44081a; color: #b82020; }
#volume.vol-95:hover  { background: #42081e; color: #e0306a; }
#volume.vol-100:hover { background: #400826; color: ${p.CRITICAL}; border-color: rgba(240,64,160,0.4); }

/* -----------------------------------------------------------------
   Media player — dim at rest, status color on hover
   ----------------------------------------------------------------- */
#mpris          { color: ${p.MUTED_ICON}; }
#mpris.stopped  { opacity: 0.45; }
#mpris:hover    { color: ${p.TEXT}; background: ${p.OVERLAY}; border-color: rgba(${p.BORDER_ACCENT_RGB},0.25); box-shadow: 0 1px 0 rgba(255,255,255,0.08) inset, 0 3px 10px rgba(${p.BORDER_ACCENT_RGB},0.15), 0 3px 8px rgba(0,0,0,0.6); }

/* -----------------------------------------------------------------
   Network — dim at rest, signal-strength color on hover
   ----------------------------------------------------------------- */
#network                    { color: ${p.MUTED_ICON}; }
#network.wifi.low:hover     { color: ${p.WARNING}; background: #2c2010; border-color: rgba(240,160,32,0.2); }
#network.wifi.mid:hover     { color: ${p.CAUTION}; background: #1e2810; border-color: rgba(200,219,56,0.16); }
#network.wifi.high:hover    { color: #7ab3c0; background: #182630; border-color: rgba(122,179,192,0.16); }
#network.wifi.full:hover    { color: ${p.FOAM}; background: ${p.TINT_PINE_MID}; border-color: rgba(156,207,216,0.2); }
#network.wired:hover        { color: ${p.FOAM}; background: ${p.TINT_PINE_MID}; border-color: rgba(156,207,216,0.18); }
#network.vpn:hover          { color: ${p.CAUTION}; background: #1e2810; border-color: rgba(200,219,56,0.18); }
#network.offline            { opacity: 0.45; }
#network.offline:hover      { opacity: 0.7; color: ${p.MUTED}; }

/* -----------------------------------------------------------------
   Bluetooth — dim at rest, state color on hover
   ----------------------------------------------------------------- */
#bluetooth      { color: ${p.MUTED_ICON}; }
#bluetooth.off  { opacity: 0.45; }
#bluetooth:hover { color: ${p.TEXT}; background: ${p.OVERLAY}; border-color: rgba(${p.BORDER_ACCENT_RGB},0.25); box-shadow: 0 1px 0 rgba(255,255,255,0.08) inset, 0 3px 10px rgba(${p.BORDER_ACCENT_RGB},0.15), 0 3px 8px rgba(0,0,0,0.6); }

/* -----------------------------------------------------------------
   Workspaces — inactive dim, active always lit
   ----------------------------------------------------------------- */
.workspaces {
  background: transparent;
  padding: 0;
  margin: 0;
  border: none;
  box-shadow: none;
}

.workspaces .item {
  background: transparent;
  color: ${p.MUTED};
  padding: 0 7px;
  margin: 0 1px;
  border-radius: 6px;
  border: 1px solid transparent;
  transition: background 0.1s ease, color 0.1s ease;
}

.workspaces .item.active {
  background: ${p.OVERLAY};
  color: ${p.TEXT};
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.35);
  box-shadow: 0 0 8px rgba(${p.BORDER_ACCENT_RGB},0.2);
}

.workspaces .item:hover {
  background: ${p.GRAD_BASE_HI};
  color: ${p.MUTED_ICON};
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.18);
}

/* -----------------------------------------------------------------
   Tray
   ----------------------------------------------------------------- */
#tray .passive        { -gtk-icon-effect: dim; }
#tray .needs-attention { -gtk-icon-effect: highlight; }

/* -----------------------------------------------------------------
   Popup windows
   The bar window is transparent via compositor; popup windows
   opened by ironbar also inherit window{background:transparent}.
   window.popup overrides that with the dark theme background.
   ----------------------------------------------------------------- */
window.popup {
  background: linear-gradient(180deg, ${p.GRAD_SURFACE_HI} 0%, ${p.GRAD_SURFACE_LO} 100%);
  border-radius: 10px;
  border: 1px solid rgba(${p.BORDER_ACCENT_RGB},0.25);
  box-shadow:
    0 0 0 1px rgba(0,0,0,0.55),
    0 4px 16px rgba(${p.BORDER_ACCENT_RGB},0.12),
    0 8px 24px rgba(0,0,0,0.70);
  color: ${p.TEXT};
}

/* Inner popup container ironbar wraps content in */
.popup {
  background: transparent;
  padding: 8px;
  color: ${p.TEXT};
}

/* Sliders (volume, brightness) inside popups */
.popup scale trough {
  background: rgba(255,255,255,0.08);
  border-radius: 4px;
  min-height: 4px;
}
.popup scale trough highlight {
  background: ${p.FOAM};
  border-radius: 4px;
}
.popup scale slider {
  background: ${p.TEXT};
  border-radius: 50%;
  min-width: 14px;
  min-height: 14px;
  box-shadow: 0 1px 4px rgba(0,0,0,0.5);
}

/* Dropdown / combobox (device selector) inside popups */
.popup combobox button,
.popup .combo button {
  background: rgba(255,255,255,0.06);
  color: ${p.TEXT};
  border: 1px solid rgba(${p.BORDER_ACCENT_RGB},0.25);
  border-radius: 6px;
}
.popup combobox button:hover,
.popup .combo button:hover {
  background: rgba(255,255,255,0.12);
  border-color: rgba(${p.BORDER_ACCENT_RGB},0.40);
}

/* Dropdown list (the actual menu that opens from the combobox) */
popover,
popover.background {
  background: ${p.GRAD_SURFACE_LO};
  border: 1px solid rgba(${p.BORDER_ACCENT_RGB},0.25);
  border-radius: 8px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.6);
  color: ${p.TEXT};
}
popover > contents {
  background: transparent;
  padding: 4px;
}
popover modelbutton,
popover row {
  border-radius: 5px;
  padding: 4px 8px;
  color: ${p.MUTED_ICON};
}
popover modelbutton:hover,
popover row:hover {
  background: rgba(${p.BORDER_ACCENT_RGB},0.15);
  color: ${p.TEXT};
}
''
