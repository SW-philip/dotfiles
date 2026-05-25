p: ''
/* ── Reset Firefox chrome defaults ──────────────────────── */
:root {
  --toolbar-bgcolor: ${p.BASE} !important;
  --toolbar-color: ${p.TEXT} !important;
  --tab-selected-bgcolor: ${p.SURFACE} !important;
  /* Modern URL bar variables */
  --urlbar-box-bgcolor: ${p.OVERLAY} !important;
  --urlbar-box-focus-bgcolor: ${p.OVERLAY} !important;
  --urlbar-box-hover-bgcolor: ${p.HIGHLIGHT_LOW} !important;
  --urlbar-box-active-bgcolor: ${p.HIGHLIGHT_MED} !important;
  --urlbar-popup-bgcolor: ${p.SURFACE} !important;
  --urlbar-popup-color: ${p.TEXT} !important;
  /* Legacy LWT variables — some LibreWolf builds read these instead */
  --lwt-toolbar-field-background-color: ${p.OVERLAY} !important;
  --lwt-toolbar-field-focus: ${p.OVERLAY} !important;
  --lwt-toolbar-field-color: ${p.TEXT} !important;
  --lwt-toolbar-field-focus-color: ${p.TEXT} !important;
}

/* ── Tab bar ─────────────────────────────────────────────── */
#TabsToolbar {
  background-color: ${p.BASE} !important;
  border-bottom: 1px solid ${p.OVERLAY} !important;
}

.tab-background {
  background-color: transparent !important;
  border-radius: 6px 6px 0 0 !important;
  border: none !important;
}

.tabbrowser-tab[selected="true"] .tab-background {
  background-color: ${p.SURFACE} !important;
  box-shadow: inset 0 2px 0 ${p.IRIS} !important;
}

.tabbrowser-tab:not([selected]):hover .tab-background {
  background-color: ${p.HIGHLIGHT_LOW} !important;
}

.tab-label {
  color: ${p.SUBTLE} !important;
}

.tabbrowser-tab[selected="true"] .tab-label {
  color: ${p.TEXT} !important;
}

.tabbrowser-tab[attention] .tab-label {
  color: ${p.GOLD} !important;
}

/* ── Nav / URL bar ───────────────────────────────────────── */
#nav-bar {
  background-color: ${p.BASE} !important;
  border-bottom: 1px solid ${p.OVERLAY} !important;
  box-shadow: none !important;
}

#urlbar {
  background-color: ${p.OVERLAY} !important;
  border: 1px solid ${p.HIGHLIGHT_MED} !important;
  border-radius: 8px !important;
  color: ${p.TEXT} !important;
  -moz-appearance: none !important;
}

#urlbar[focused="true"],
#urlbar[open] {
  border-color: ${p.IRIS} !important;
  box-shadow: 0 0 0 2px rgba(${p.BORDER_IRIS_RGB}, 0.25) !important;
}

/* -moz-appearance: none strips the native UA draw call that can paint white
   over background-color regardless of !important specificity. */
#urlbar-background {
  background-color: ${p.OVERLAY} !important;
  -moz-appearance: none !important;
  border: none !important;
}

#urlbar[focused="true"] #urlbar-background,
#urlbar[open] #urlbar-background {
  background-color: ${p.OVERLAY} !important;
}

#urlbar-input-container {
  background-color: transparent !important;
  color: ${p.TEXT} !important;
}

#urlbar-input {
  color: ${p.TEXT} !important;
  background-color: transparent !important;
  -moz-appearance: none !important;
}

#urlbar-input::placeholder {
  color: ${p.MUTED} !important;
  opacity: 1 !important;
}

.urlbar-icon,
.urlbar-icon-wrapper {
  color: ${p.MUTED} !important;
  fill: ${p.MUTED} !important;
}

/* ── URL bar dropdown (suggestions panel) ────────────────── */
.urlbarView {
  background-color: ${p.SURFACE} !important;
  color: ${p.TEXT} !important;
  -moz-appearance: none !important;
  border: 1px solid ${p.OVERLAY} !important;
  border-top: none !important;
  border-radius: 0 0 8px 8px !important;
}

.urlbarView-body-inner {
  background-color: transparent !important;
}

.urlbarView-results {
  background-color: transparent !important;
  padding: 4px !important;
}

.urlbarView-row {
  background-color: transparent !important;
  border-radius: 4px !important;
}

.urlbarView-row[selected],
.urlbarView-row:hover {
  background-color: ${p.HIGHLIGHT_LOW} !important;
}

.urlbarView-row-inner {
  color: ${p.TEXT} !important;
}

.urlbarView-title,
.urlbarView-title-separator,
.urlbarView-secondary {
  color: ${p.SUBTLE} !important;
}

.urlbarView-url {
  color: ${p.FOAM} !important;
}

.urlbarView-row[selected] .urlbarView-title,
.urlbarView-row[selected] .urlbarView-url,
.urlbarView-row[selected] .urlbarView-secondary {
  color: ${p.TEXT} !important;
}

/* ── Bookmarks / personal toolbar ────────────────────────── */
#PersonalToolbar {
  background-color: ${p.BASE} !important;
  border-bottom: 1px solid ${p.OVERLAY} !important;
}

.bookmark-item > .toolbarbutton-text {
  color: ${p.SUBTLE} !important;
}

.bookmark-item:hover > .toolbarbutton-text {
  color: ${p.TEXT} !important;
}

/* ── Toolbar buttons ─────────────────────────────────────── */
#nav-bar .toolbarbutton-1 {
  color: ${p.SUBTLE} !important;
  fill: ${p.SUBTLE} !important;
  border-radius: 6px !important;
}

#nav-bar .toolbarbutton-1:hover {
  background-color: ${p.HIGHLIGHT_LOW} !important;
  color: ${p.TEXT} !important;
  fill: ${p.TEXT} !important;
}

#nav-bar .toolbarbutton-1[open],
#nav-bar .toolbarbutton-1:active {
  background-color: ${p.HIGHLIGHT_MED} !important;
  color: ${p.IRIS} !important;
  fill: ${p.IRIS} !important;
}

/* ── Sidebar ─────────────────────────────────────────────── */
#sidebar-box {
  background-color: ${p.SURFACE} !important;
  border-right: 1px solid ${p.OVERLAY} !important;
}

#sidebar-header {
  background-color: ${p.BASE} !important;
  color: ${p.TEXT} !important;
  border-bottom: 1px solid ${p.OVERLAY} !important;
}

/* ── Find bar ────────────────────────────────────────────── */
.findbar-container {
  background-color: ${p.OVERLAY} !important;
  border-top: 1px solid ${p.HIGHLIGHT_MED} !important;
}

.findbar-textbox {
  background-color: ${p.SURFACE} !important;
  color: ${p.TEXT} !important;
  border: 1px solid ${p.HIGHLIGHT_MED} !important;
  border-radius: 4px !important;
}
''
