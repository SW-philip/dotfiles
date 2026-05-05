# Family Theme Picker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give the family machine a GUI theme picker — a floating GTK3 window with one big button per Lix theme, each labeled in that theme's accent color, launched from a waybar button.

**Architecture:** A new `home/family/themes.nix` module auto-discovers every complete theme under `themes/Lix/` at Nix eval time, pre-generates all config files as store paths, bakes a `set-theme-family` shell script and a `theme-picker` Python GTK3 app into the store, and wires up a waybar button to launch the picker. Adding or removing a Lix theme folder and running `nrs` on family is all that's needed — no manual code edits.

**Tech Stack:** Nix/home-manager, Python 3 + PyGObject (GTK3), swaybg, systemd user services, waybar custom modules

**Design doc:** `docs/plans/2026-04-25-family-theme-picker-design.md`

---

### Task 1: Add theme-picker float rule to `home/niri/config.kdl.nix`

Harmless on desktop/surface (app never opens there). Needed so niri floats the picker window on family.

**Files:**
- Modify: `home/niri/config.kdl.nix` (around line 125, after the existing `window-rule` block)

**Step 1: Add the window-rule**

In `config.kdl.nix`, after the existing `window-rule { match is-floating=true ... }` block (after line 137), insert:

```
// ── Theme picker — always floating ────────────────────────
window-rule {
    match app-id="theme-picker"
    open-floating true
}
```

**Step 2: Commit**

```bash
git add home/niri/config.kdl.nix
git commit -m "feat(niri): float rule for theme-picker app-id"
```

---

### Task 2: Create `home/family/themes.nix`

The core module. Contains Lix theme auto-discovery, config generators, the `set-theme-family` script, the `theme-picker` GTK3 app, and the swaybg systemd service.

**Files:**
- Create: `home/family/themes.nix`

**Step 1: Write the module**

```nix
# home/family/themes.nix
# Lix-only theme system for the family machine.
# Auto-discovers themes/Lix/<folder>/ at build time — no edits needed when themes are added/removed.
{ pkgs, lib, ... }:
let
  lixRoot = ../../themes/Lix;

  # ── Auto-discovery ───────────────────────────────────────────────────────────
  # Loads every Lix subfolder that contains a palette-*.nix file.
  # Skips empty dirs (butterCream, butterscotch).
  # Returns { slug → { slug, folderName, wallpaper, palette, shContent } }
  lixThemes =
    let
      dirs = lib.filterAttrs (_: t: t == "directory") (builtins.readDir lixRoot);

      loadTheme = folderName:
        let
          dir   = "${lixRoot}/${folderName}";
          files = builtins.readDir dir;
          nixFiles = lib.filterAttrs (n: _: lib.hasPrefix "palette-" n && lib.hasSuffix ".nix" n) files;
        in
        if nixFiles == {} then null   # skip empty dirs
        else
          let
            nixName  = builtins.head (builtins.attrNames nixFiles);
            slug     = lib.removeSuffix ".nix" (lib.removePrefix "palette-" nixName);
            shName   = builtins.head (builtins.attrNames (
                         lib.filterAttrs (n: _: lib.hasPrefix "palette-" n && lib.hasSuffix ".sh" n) files));
            wpFiles  = lib.filterAttrs (n: _: lib.hasPrefix "wallpaper-" n && lib.hasSuffix ".png" n) files;
            wallpaper = if wpFiles != {}
                        then "${dir}/${builtins.head (builtins.attrNames wpFiles)}"
                        else null;
            palette  = import "${dir}/${nixName}";
          in {
            inherit slug folderName wallpaper palette;
            shContent = builtins.readFile "${dir}/${shName}";
          };

      loaded = lib.mapAttrs (folder: _: loadTheme folder) dirs;
    in
    # Re-key by slug; drop nulls (empty dirs)
    lib.foldlAttrs (acc: _folder: v:
      if v == null then acc
      else acc // { ${v.slug} = v; }
    ) {} loaded;

  # ── Config generators ────────────────────────────────────────────────────────
  mkMakoConfig = p: subtleBorder: faintBorder: ''
    default-timeout=5000
    width=400
    margin=16
    padding=12
    border-size=1
    border-radius=7
    sort=-time
    max-visible=5
    font=JetBrains Mono 11
    background-color=${p.SURFACE}ff
    text-color=${p.TEXT}ff
    border-color=${subtleBorder}
    progress-color=over ${p.TINT_PINE_DARK}ff

    [app-name=sqlch]
    default-timeout=8000
    border-size=2
    border-color=${p.FOAM}aa
    background-color=${p.TINT_PINE_MID}ff
    text-color=${p.FOAM}ff

    [urgency=low]
    background-color=${p.BASE}ff
    text-color=${p.SUBTLE}ff
    border-color=${faintBorder}
    default-timeout=3000

    [urgency=normal]
    background-color=${p.SURFACE}ff
    text-color=${p.TEXT}ff
    border-color=${subtleBorder}

    [urgency=critical]
    background-color=${p.TINT_CRITICAL_BG}ff
    text-color=${p.CRITICAL}ff
    border-color=${p.CRITICAL}59
    default-timeout=0

    [mode=do-not-disturb]
    invisible=1
  '';

  mkGhosttyConfig = p: ''
    palette = 0=${p.OVERLAY}
    palette = 1=${p.LOVE}
    palette = 2=${p.PINE}
    palette = 3=${p.GOLD}
    palette = 4=${p.FOAM}
    palette = 5=${p.IRIS}
    palette = 6=${p.ROSE}
    palette = 7=${p.TEXT}
    palette = 8=${p.HIGHLIGHT_LOW}
    palette = 9=${p.LOVE}
    palette = 10=${p.PINE}
    palette = 11=${p.GOLD}
    palette = 12=${p.FOAM}
    palette = 13=${p.IRIS}
    palette = 14=${p.ROSE}
    palette = 15=${p.TEXT}

    background = ${p.BASE}
    foreground = ${p.TEXT}

    cursor-color = ${p.IRIS}
    cursor-text = ${p.BASE}

    selection-background = ${p.HIGHLIGHT_MED}
    selection-foreground = ${p.TEXT}

    window-padding-x = 12
    window-padding-y = 8
  '';

  # ── Per-theme store-path configs ─────────────────────────────────────────────
  themeConfigs = lib.mapAttrs (slug: t:
    let
      subtleBorder = if t.palette.isLight or false then "#0000000a" else "#ffffff0a";
      faintBorder  = if t.palette.isLight or false then "#00000006" else "#ffffff06";
    in {
      mako          = pkgs.writeText "mako-${slug}"      (mkMakoConfig t.palette subtleBorder faintBorder);
      niriKdl       = pkgs.writeText "niri-${slug}.kdl"  (import ../niri/config.kdl.nix { p = t.palette; barHeight = 64; });
      waybarCss     = pkgs.writeText "waybar-${slug}.css" (import ../waybar/style.nix t.palette);
      waybarSh      = pkgs.writeText "waybar-${slug}.sh"  t.shContent;
      ghostty       = pkgs.writeText "ghostty-${slug}"   (mkGhosttyConfig t.palette);
      wallpaperPath = if t.wallpaper != null then t.wallpaper else "";
    }
  ) lixThemes;

  # ── swaybg launcher — reads path from state file at runtime ──────────────────
  swaybgLauncher = pkgs.writeShellScript "swaybg-launcher-family" ''
    exec ${pkgs.swaybg}/bin/swaybg -o '*' -i "$(cat "$HOME/.local/state/wallpaper")" -m fill
  '';

  # ── set-theme-family ─────────────────────────────────────────────────────────
  setThemeFamily = pkgs.writeShellScriptBin "set-theme-family" (
    ''
      THEME="''${1:-}"
      if [ -z "$THEME" ]; then
        echo "Usage: set-theme-family <theme>" >&2
        echo "Available: ${lib.concatStringsSep "  " (lib.attrNames themeConfigs)}" >&2
        exit 1
      fi

      case "$THEME" in
    ''
    + lib.concatStrings (lib.mapAttrsToList (slug: cfgs: ''
        ${slug})
          MAKO_CFG="${cfgs.mako}"
          NIRI_CFG="${cfgs.niriKdl}"
          WAYBAR_CSS="${cfgs.waybarCss}"
          WAYBAR_PALETTE="${cfgs.waybarSh}"
          GHOSTTY_CFG="${cfgs.ghostty}"
          WALLPAPER_PATH="${cfgs.wallpaperPath}"
          ;;
      '') themeConfigs)
    + ''
        *)
          echo "Unknown theme: ''${THEME}" >&2
          echo "Available: ${lib.concatStringsSep "  " (lib.attrNames themeConfigs)}" >&2
          exit 1
          ;;
      esac

      echo "''${THEME}" > "$HOME/.local/state/theme"

      # Hide waybar immediately to avoid visual jitter during swap
      pkill -SIGUSR1 waybar 2>/dev/null || true

      # mako
      cp --remove-destination "$MAKO_CFG" "$HOME/.config/mako/config"
      makoctl reload 2>/dev/null || true

      # waybar CSS + palette (reload sent last — see SIGUSR2 note below)
      cp --remove-destination "$WAYBAR_CSS" "$HOME/.config/waybar/style.css"
      cp --remove-destination "$WAYBAR_PALETTE" "$HOME/.config/waybar/palette.sh"

      # niri border colors
      rm -f "$HOME/.config/niri/config.kdl"
      cp "$NIRI_CFG" "$HOME/.config/niri/config.kdl"
      # Re-append xrdb spawn (niriXresources activation appends this at build time;
      # must be re-added every time the config file is replaced at runtime)
      echo 'spawn-at-startup "xrdb" "-merge" "''$HOME/.Xresources"' >> "$HOME/.config/niri/config.kdl"
      niri msg action reload-config 2>/dev/null || true

      # ghostty
      mkdir -p "$HOME/.config/ghostty"
      cp --remove-destination "$GHOSTTY_CFG" "$HOME/.config/ghostty/config"
      ghostty +reload-config 2>/dev/null || true

      # wallpaper
      if [ -n "$WALLPAPER_PATH" ]; then
        mkdir -p "$HOME/.local/state"
        echo "$WALLPAPER_PATH" > "$HOME/.local/state/wallpaper"
        systemctl --user restart swaybg 2>/dev/null || true
      fi

      sleep 0.4

      # waybar SIGUSR2 MUST be last — it restarts waybar which sends SIGTERM to all
      # children including this script. Everything above must finish first.
      pkill -SIGUSR2 waybar 2>/dev/null || true
    ''
  );

  # ── theme-picker GTK3 app ────────────────────────────────────────────────────
  # Theme list baked at build time: (slug, display_name, iris_color)
  themesForPicker = lib.sortBy (a: b: a.slug < b.slug)
    (lib.mapAttrsToList (slug: t: {
      inherit slug;
      displayName = t.folderName;
      color       = t.palette.IRIS;
    }) lixThemes);

  themeListPy = lib.concatStringsSep "\n    "
    (map (t: ''("${t.slug}", "${t.displayName}", "${t.color}"),'' ) themesForPicker);

  pythonEnv = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);

  themePicker = pkgs.writeScriptBin "theme-picker" ''
    #!${pythonEnv}/bin/python3
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk, Gdk, Pango
    import subprocess

    THEMES = [
        ${themeListPy}
    ]

    CSS = b"""
    window {
        background-color: #1a1426;
    }
    .picker-title {
        color: #e0def4;
        font-size: 18px;
        font-weight: bold;
        padding: 8px 0 16px 0;
    }
    .theme-btn {
        background: #2a2437;
        border: 1px solid #3a3450;
        border-radius: 10px;
        padding: 0;
        min-width: 180px;
        min-height: 64px;
    }
    .theme-btn:hover {
        background: #3a3450;
        border-color: #5a5470;
    }
    """

    class ThemePickerApp(Gtk.Application):
        def __init__(self):
            super().__init__(application_id="theme-picker")

        def do_activate(self):
            win = Gtk.ApplicationWindow(application=self, title="Choose Theme")
            win.set_resizable(False)
            win.set_default_size(420, -1)

            provider = Gtk.CssProvider()
            provider.load_from_data(CSS)
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
            )

            win.connect("key-press-event", self._on_key)

            outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
            outer.set_margin_top(20)
            outer.set_margin_bottom(20)
            outer.set_margin_start(20)
            outer.set_margin_end(20)

            title = Gtk.Label(label="Choose Theme")
            title.get_style_context().add_class("picker-title")
            outer.pack_start(title, False, False, 0)

            flow = Gtk.FlowBox()
            flow.set_max_children_per_line(4)
            flow.set_min_children_per_line(2)
            flow.set_column_spacing(10)
            flow.set_row_spacing(10)
            flow.set_homogeneous(True)
            flow.set_selection_mode(Gtk.SelectionMode.NONE)

            for slug, display_name, color in THEMES:
                btn = Gtk.Button()
                btn.get_style_context().add_class("theme-btn")
                lbl = Gtk.Label()
                lbl.set_markup(
                    f'<span foreground="{color}" size="large" weight="bold">{display_name}</span>'
                )
                btn.add(lbl)
                btn.connect("clicked", self._pick, slug, win)
                flow.add(btn)

            outer.pack_start(flow, True, True, 0)
            win.add(outer)
            win.show_all()

        def _pick(self, _btn, slug, win):
            subprocess.Popen(["set-theme-family", slug])
            win.close()

        def _on_key(self, win, event):
            if event.keyval == Gdk.KEY_Escape:
                win.close()

    ThemePickerApp().run()
  '';

in
{
  # ── Packages ────────────────────────────────────────────────────────────────
  home.packages = [ setThemeFamily themePicker pkgs.swaybg ];

  # ── swaybg systemd service ──────────────────────────────────────────────────
  systemd.user.services.swaybg = {
    Unit = {
      Description = "swaybg wallpaper (family)";
      After  = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${swaybgLauncher}";
      Restart    = "on-failure";
      RestartSec = "2s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # ── Activation: write configs for current theme (default: clementine) ────────
  # Named "niriCfg" so the existing niriXresources activation (entryAfter ["niriCfg"])
  # in default.nix continues to work without changes.
  home.activation.niriCfg = lib.hm.dag.entryAfter ["writeBoundary"] ''
    STATE="$HOME/.local/state/theme"
    THEME=$(cat "$STATE" 2>/dev/null || echo "clementine")

    # Validate — fall back to clementine if state holds an unknown slug
    case "$THEME" in
      ${lib.concatStringsSep "|" (lib.attrNames themeConfigs)}) ;;
      *) THEME="clementine" ;;
    esac

    # Re-run set-theme-family to apply the stored theme
    $DRY_RUN_CMD ${setThemeFamily}/bin/set-theme-family "$THEME" || true
  '';
}
```

**Step 2: Commit**

```bash
git add home/family/themes.nix
git commit -m "feat(family): themes.nix — Lix auto-discovery, set-theme-family, theme-picker"
```

---

### Task 3: Wire `themes.nix` into `home/family/default.nix`

**Files:**
- Modify: `home/family/default.nix`

**Step 1: Add the import and remove the hardcoded niriCfg activation**

Add `./themes.nix` to the `imports` list (alongside `./waybar.nix` and `../mako`).

Remove the entire `home.activation.niriCfg` block (lines 25–41) — `themes.nix` now owns it under the same name.

Keep `home.activation.niriXresources` exactly as-is — it depends on `"niriCfg"` which `themes.nix` provides.

**Step 2: Commit**

```bash
git add home/family/default.nix
git commit -m "feat(family): import themes.nix, remove hardcoded niriCfg activation"
```

---

### Task 4: Update `home/family/waybar.nix`

Add the theme-picker waybar button and remove the hardcoded `waybarStyleCss` activation (themes.nix writes CSS+palette at activation time).

**Files:**
- Modify: `home/family/waybar.nix`

**Step 1: Add the theme button to `modules-left`**

In `settings.mainBar`, change `modules-left` from `["custom/start"]` to:

```nix
modules-left = [
  "custom/start"
  "custom/theme"
];
```

Add the module definition alongside `custom/start`:

```nix
"custom/theme" = {
  exec        = ''echo '{"text": "󰔎  Theme"}'  '';
  on-click    = "theme-picker";
  return-type = "json";
  interval    = "once";
};
```

**Step 2: Remove the `waybarStyleCss` activation block**

Delete the entire `home.activation.waybarStyleCss` block (lines 87–97). `themes.nix`'s activation now calls `set-theme-family` which writes both `style.css` and `palette.sh`.

**Step 3: Commit**

```bash
git add home/family/waybar.nix
git commit -m "feat(family): add theme-picker waybar button, remove hardcoded waybarStyleCss"
```

---

### Task 5: Rebuild and test on family

**Step 1: Push from dev machine**

```bash
git push
```

**Step 2: Pull and rebuild on family**

On the family machine:

```bash
cd ~/nixos && git pull && sudo nixos-rebuild switch --flake .#family
```

**Step 3: Verify set-theme-family works from terminal first**

```bash
set-theme-family clementine
```

Expected: mako, niri, waybar, ghostty, wallpaper all update. `~/.local/state/theme` contains `clementine`.

**Step 4: Verify the picker launches**

```bash
theme-picker
```

Expected: a floating dark window with buttons labeled in accent colors, one per Lix theme.

**Step 5: Click a theme button**

Expected: theme switches, picker closes.

**Step 6: Verify the waybar button works**

Click "󰔎  Theme" in the waybar. Expected: picker opens as a floating window.

**Step 7: Rebuild with a new theme to verify auto-discovery**

On dev machine: add a file to `themes/Lix/rockyRoad/` (or any already-complete theme that you haven't tested yet). Push. Pull on family. `nrs`. Verify the picker now shows it.

---

## Notes

- `butterCream` and `butterscotch` are empty dirs — auto-discovery skips them. Once palette files are added, they'll appear in the picker automatically.
- The `set-theme-family` script re-appends the xrdb `spawn-at-startup` line every time it writes the niri config. This is intentional — it mirrors the `niriXresources` activation behavior.
- swaybg uses `-o '*'` (all outputs) since the family TV output name may vary.
- The `niriCfg` activation name is preserved intentionally to keep the `niriXresources` dependency chain working without touching `default.nix` further.
