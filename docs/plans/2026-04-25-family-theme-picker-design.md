# Family Theme Picker — Design

**Date:** 2026-04-25
**Goal:** Give Clem a GUI theme switcher on the family machine. Lix themes only. No terminal required.

---

## Architecture

New file `home/family/themes.nix`, imported by `home/family/default.nix`.

At Nix eval time it:
1. Reads `themes/Lix/` and discovers every subfolder containing a `palette-*.nix` file. Skips empty dirs (e.g. `butterCream`, `butterscotch`).
2. For each discovered theme, pre-generates store-path config files: niri KDL, mako config, waybar CSS, waybar palette.sh, ghostty config. Same pattern as `themeConfigs` in `home/niri/default.nix`.
3. Bakes two scripts into the store:
   - `set-theme-family` — takes a slug arg, swaps all configs, reloads services (mako reload, niri reload-config, waybar SIGUSR2, ghostty reload-config, swaybg restart via systemd)
   - `theme-picker` — Python GTK3 floating window; calls `set-theme-family <slug>` on click, then closes
4. Adds a `custom/theme` waybar module to the family bar that `exec`s `theme-picker`.
5. Adds a niri `window-rule` to float the picker (matched by `app-id "theme-picker"`).

**Adding/removing a theme:** drop or remove files in `themes/Lix/<folder>/`, push to git, pull on family, `nrs`. No other changes needed — auto-discovery handles it.

---

## set-theme-family Script

Shell script (`pkgs.writeShellScriptBin "set-theme-family"`). Baked slugs and store paths are embedded at build time via Nix string interpolation (same technique as `set-theme` in `home/niri/default.nix`).

Services reloaded per swap:
- **mako** — `cp` config + `makoctl reload`
- **niri** — `cp` config + `niri msg action reload-config`
- **waybar** — `cp` CSS + `cp` palette.sh + hide via `SIGUSR1` before work, `SIGUSR2` (restart) last
- **ghostty** — `cp` config + `ghostty +reload-config`
- **wallpaper** — write path to `~/.local/state/wallpaper` + `systemctl --user restart swaybg`

Writes current slug to `~/.local/state/theme` (same convention as desktop/surface).

---

## theme-picker UI

Python GTK3 script, wrapped with `pkgs.python3.withPackages [pygobject3]` and declared via `pkgs.writeScriptBin`.

- **Window:** title `"Choose Theme"`, app-id `theme-picker`, neutral dark background, no decorations border
- **Layout:** `Gtk.FlowBox` — auto-reflows buttons into additional columns as theme count grows. Natural reflow, no fixed grid math, no scrollbar needed.
- **Buttons:** one per discovered Lix theme, alphabetical slug order
  - Large font (~22px), generous padding (~20px top/bottom)
  - Label text colored with that theme's `IRIS` color (embedded at build time)
  - Label text is the human-readable folder name (e.g. `Clementine`, `lemonSorbet`)
- **On click:** `subprocess.run(["set-theme-family", slug])` then `Gtk.main_quit()`
- **Dismiss:** Escape key or clicking outside closes without switching

---

## Waybar Integration

Add to `home/family/waybar.nix` `modules-right` (or left, TBD at implementation):

```nix
"custom/theme-picker" = {
  exec     = ''echo '{"text": "󰔎  Theme"}'  '';
  on-click = "theme-picker";
  return-type = "json";
  interval = "once";
};
```

---

## Niri Float Rule

Add to the family niri config (in the activation block or as a string appended):

```kdl
window-rule {
  match app-id="theme-picker"
  open-floating true
}
```

---

## Constraints

- Only Lix themes are exposed to the family machine — Rose-Pine variants are not shown
- `butterCream` and `butterscotch` dirs are currently empty and will be skipped by auto-discovery
- No ironbar, no pandora, no cava, no nemo on the family machine — `set-theme-family` omits all of those
- swaybg is universal across all machines now
