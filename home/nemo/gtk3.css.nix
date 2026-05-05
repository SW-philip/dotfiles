# Nemo file manager — palette-aware GTK3 CSS
# Injected via ~/.config/gtk-3.0/gtk.css; survives toggle-theme swaps.
# Selectors are Nemo-specific enough not to bleed into other GTK3 apps.
p: ''
/* ============================================================
 * NEMO — Rosé Pine colour overlays
 * GTK3-compatible CSS  (no custom properties)
 * Targets: sidebar, path-bar, views, header, statusbar
 * ============================================================ */

/* ── Sidebar ─────────────────────────────────────────────── */

placessidebar {
  background-color: ${p.SURFACE};
  border-right: 1px solid ${p.OVERLAY};
}

placessidebar > viewport > list {
  background-color: transparent;
}

/* Every sidebar row */
placessidebar > viewport > list > row {
  border-radius: 6px;
  margin: 1px 6px;
  padding: 1px 2px;
  color: ${p.SUBTLE};
  transition: background-color 0.12s ease, color 0.12s ease;
}

/* Section separator labels (Bookmarks, Devices, Network…) */
placessidebar > viewport > list > row.separator > label {
  color: ${p.MUTED};
  font-size: 10px;
  font-weight: bold;
}

placessidebar > viewport > list > row:hover {
  background-color: ${p.HIGHLIGHT_LOW};
  color: ${p.TEXT};
}

/* Selected place — IRIS wash */
placessidebar > viewport > list > row:selected,
placessidebar > viewport > list > row:selected:focus {
  background-color: rgba(${p.BORDER_IRIS_RGB}, 0.28);
  color: ${p.IRIS};
}

placessidebar > viewport > list > row:selected label,
placessidebar > viewport > list > row:selected:focus label {
  color: ${p.IRIS};
}

/* ── Path bar (breadcrumbs) ──────────────────────────────── */

.path-bar > button,
.path-bar button {
  background: none;
  box-shadow: none;
  border: none;
  border-radius: 5px;
  color: ${p.SUBTLE};
  padding: 2px 7px;
  transition: background-color 0.1s ease, color 0.1s ease;
}

.path-bar > button:hover,
.path-bar button:hover {
  background-color: ${p.HIGHLIGHT_LOW};
  color: ${p.FOAM};
}

/* The last segment (current directory) */
.path-bar > button:last-child,
.path-bar > button:checked,
.path-bar button.text-button:active {
  color: ${p.TEXT};
  font-weight: bold;
}

/* ── File / icon view ────────────────────────────────────── */

.view:selected {
  background-color: rgba(${p.BORDER_IRIS_RGB}, 0.22);
  color: ${p.TEXT};
}

.view:selected:focus {
  background-color: rgba(${p.BORDER_IRIS_RGB}, 0.32);
  outline-color: ${p.IRIS};
}

/* Rubber-band selection */
.rubberband {
  border: 1px solid ${p.IRIS};
  background-color: rgba(${p.BORDER_IRIS_RGB}, 0.14);
}

/* ── List-view rows ──────────────────────────────────────── */

treeview.view row:selected {
  background-color: rgba(${p.BORDER_IRIS_RGB}, 0.22);
  color: ${p.TEXT};
}

treeview.view row:selected:focus {
  background-color: rgba(${p.BORDER_IRIS_RGB}, 0.32);
}

treeview.view row:selected > cell {
  color: ${p.FOAM};
}

/* Column headers */
treeview.view header button {
  background: ${p.OVERLAY};
  color: ${p.SUBTLE};
  border-right: 1px solid ${p.HIGHLIGHT_MED};
}

treeview.view header button:hover {
  background: ${p.HIGHLIGHT_MED};
  color: ${p.TEXT};
}

/* ── Toolbar / header bar ────────────────────────────────── */

toolbar {
  background: linear-gradient(180deg, ${p.GRAD_SURFACE_HI} 0%, ${p.GRAD_SURFACE_LO} 100%);
  border-bottom: 1px solid ${p.OVERLAY};
}

headerbar {
  background: linear-gradient(180deg, ${p.GRAD_SURFACE_HI} 0%, ${p.GRAD_SURFACE_LO} 100%);
  border-bottom: 1px solid ${p.OVERLAY};
  color: ${p.TEXT};
}

/* Navigation buttons (back / forward / up) */
headerbar button.image-button,
toolbar button.image-button {
  color: ${p.SUBTLE};
  border-radius: 5px;
  transition: color 0.12s ease, background-color 0.12s ease;
}

headerbar button.image-button:hover,
toolbar button.image-button:hover {
  color: ${p.FOAM};
  background-color: ${p.HIGHLIGHT_LOW};
}

/* ── Statusbar ───────────────────────────────────────────── */

.statusbar,
statusbar {
  background-color: ${p.SURFACE};
  border-top: 1px solid ${p.OVERLAY};
  color: ${p.MUTED};
  font-size: 11px;
  padding: 2px 8px;
}

/* ── Notebook tabs (if Nemo is opened with multiple tabs) ── */

notebook > header {
  background-color: ${p.BASE};
  border-bottom: 1px solid ${p.OVERLAY};
}

notebook > header > tabs > tab {
  color: ${p.MUTED};
  padding: 4px 12px;
  border-radius: 5px 5px 0 0;
}

notebook > header > tabs > tab:hover {
  color: ${p.SUBTLE};
  background-color: ${p.HIGHLIGHT_LOW};
}

notebook > header > tabs > tab:checked {
  background-color: ${p.SURFACE};
  color: ${p.IRIS};
  border-bottom: 2px solid ${p.IRIS};
}

/* ── Context menu polish ─────────────────────────────────── */

menu {
  background-color: ${p.OVERLAY};
  border: 1px solid ${p.HIGHLIGHT_MED};
  border-radius: 6px;
  padding: 4px;
}

menu > menuitem {
  border-radius: 4px;
  color: ${p.TEXT};
  padding: 3px 10px;
}

menu > menuitem:hover {
  background-color: rgba(${p.BORDER_IRIS_RGB}, 0.22);
  color: ${p.IRIS};
}

menu > separator {
  background-color: ${p.HIGHLIGHT_MED};
  margin: 4px 8px;
}

/* ── Tooltips ────────────────────────────────────────────── */

tooltip {
  background-color: ${p.OVERLAY};
  border: 1px solid ${p.HIGHLIGHT_MED};
  border-radius: 6px;
  padding: 4px 8px;
}

tooltip * {
  color: ${p.TEXT};
}
''
