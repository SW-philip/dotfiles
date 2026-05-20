{ p, l, barHeight ? 45, cursorSize ? 48, isDesktop ? false }: ''
// home/niri/config.kdl — niri cleanroom compositor config

// ── Input ──────────────────────────────────────────────────
input {
    keyboard {
        xkb {
            layout "us"
        }
        repeat-delay 250
        repeat-rate 40
    }

    touchpad {
        tap
        natural-scroll
        scroll-factor 0.6
    }

    mouse {
        accel-speed 0.0
    }

    focus-follows-mouse max-scroll-amount="0%"
}

// ── Environment propagation ────────────────────────────────
spawn-at-startup "systemctl" "--user" "import-environment" "PATH" "DISPLAY" "WAYLAND_DISPLAY" "XDG_SESSION_DESKTOP" "XDG_CURRENT_DESKTOP" "XDG_RUNTIME_DIR"
spawn-at-startup "dbus-update-activation-environment" "--systemd" "PATH" "DISPLAY" "WAYLAND_DISPLAY" "XDG_SESSION_DESKTOP" "XDG_CURRENT_DESKTOP" "XDG_RUNTIME_DIR"

// ── XWayland bridge ────────────────────────────────────────
// xwayland-satellite provides rootful XWayland for X11 apps under niri
spawn-at-startup "xwayland-satellite"

// ── Outputs ────────────────────────────────────────────────
// Desktop: dual 1080p
output "DP-3" {
    mode "1920x1080@60.000"
    position x=1920 y=0
    scale 1.0
}
output "DP-4" {
    mode "1920x1080@60.000"
    position x=0 y=0
    scale 1.0
}
// Surface: HiDPI internal display
output "eDP-1" {
    mode "2736x1824@60.000"
    scale 2.0
}
// Family: 65" Samsung 4K TV — scale 3.0 makes 4K appear as 1280×720 logical (couch-readable)
// If still too small try scale 2.5 (→ 1536×864). Check name with: niri msg outputs
output "HDMI-A-1" {
    scale 3.0
}

// ── Layout ────────────────────────────────────────────────
layout {
    gaps ${toString l.gap}

    border {
        width ${toString l.borderW}
        active-color "${p.IRIS}"
        inactive-color "${p.INACTIVE_BORDER}"
        urgent-color "${p.LOVE}"
    }

    focus-ring {
        off
    }

    preset-column-widths {
        proportion 0.333
        proportion 0.5
        proportion 0.666
        proportion 1.0
    }

    default-column-width { proportion 0.5; }

    struts {
        top 0
        bottom 0
    }
}

// ── Appearance ────────────────────────────────────────────
prefer-no-csd

cursor {
    xcursor-theme "posys_cursor_scalable"
    xcursor-size ${toString cursorSize}
}

environment {
    XCURSOR_THEME "posys_cursor_scalable"
    XCURSOR_SIZE "${toString cursorSize}"
    XDG_CURRENT_DESKTOP "niri"
    // xwayland-satellite binds to :0; set DISPLAY here so all niri-spawned
    // apps (Steam, etc.) inherit it rather than racing import-environment.
    DISPLAY ":0"
}

// ── Animations ────────────────────────────────────────────
animations {
    slowdown 0.8

    workspace-switch {
        spring damping-ratio=1.0 stiffness=800 epsilon=0.001
    }
    window-open {
        duration-ms 150
    }
    window-close {
        duration-ms 100
    }
}

// ── Window rules ──────────────────────────────────────────
// Lock windows to the right side of the left monitor (DP-4)
window-rule {
    match on-output="eDP-1"
    window-column-alignment "center"
}

window-rule {
    match on-output="DP-4"
    window-column-alignment "end"
}

// Lock windows to the left side of the right monitor (DP-3)
// This is technically the default, but explicit is better for this setup.
window-rule {
    match on-output="DP-3"
    window-column-alignment "start"
}

window-rule {
    match is-floating=true
    shadow {
        on
        softness 8
        offset x=0 y=4
        color "${p.SHADOW}80"
    }
    border {
        active-color "${p.INACTIVE_BORDER}"
    }
}

// ── Bindings ──────────────────────────────────────────────
binds {
    // Apps
    Mod+Return { spawn "ghostty"; }
    Mod+Space  { spawn "fuzzel"; }
    Mod+E      { spawn "nemo"; }
    Mod+V      { spawn "bash" "-c" "cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"; }
    ${if !isDesktop then ''Mod+Shift+W { spawn "toggle-wvkbd"; }'' else ""}

    // Windows
    Mod+Q { close-window; }
    Mod+F { fullscreen-window; }
    Mod+Shift+F  { toggle-window-floating; }
    Mod+Ctrl+F   { switch-focus-between-floating-and-tiling; }
    Mod+M        { maximize-column; }
    Mod+BracketLeft  { consume-or-expel-window-left; }
    Mod+BracketRight { consume-or-expel-window-right; }

    // Focus — hjkl or arrows
    Mod+H { focus-column-left; }
    Mod+L { focus-column-right; }
    Mod+J { focus-window-down; }
    Mod+K { focus-window-up; }
    Mod+Left  { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Down  { focus-window-down; }
    Mod+Up    { focus-window-up; }

    // Move windows
    Mod+Shift+H { move-column-left; }
    Mod+Shift+L { move-column-right; }
    Mod+Shift+J { move-window-down; }
    Mod+Shift+K { move-window-up; }

    // Resize
    Mod+R { switch-preset-column-width; }
    Mod+Shift+R { spawn "niri" "msg" "action" "load-config-file"; }
    Mod+Minus { set-column-width "-5%"; }
    Mod+Equal { set-column-width "+5%"; }
    Mod+Shift+Minus { set-window-height "-5%"; }
    Mod+Shift+Equal { set-window-height "+5%"; }

    // Workspaces
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+Shift+1 { move-column-to-workspace 1; }
    Mod+Shift+2 { move-column-to-workspace 2; }
    Mod+Shift+3 { move-column-to-workspace 3; }
    Mod+Shift+4 { move-column-to-workspace 4; }
    Mod+Shift+5 { move-column-to-workspace 5; }
    Mod+Tab              { focus-workspace-down; }
    Mod+Shift+Tab        { focus-workspace-up; }
    Mod+Ctrl+Tab         { move-column-to-workspace-down; }
    Mod+Ctrl+Shift+Tab   { move-column-to-workspace-up; }

    // Monitors
    Mod+Comma  { focus-monitor-left; }
    Mod+Period { focus-monitor-right; }
    Mod+Shift+Comma  { move-column-to-monitor-left; }
    Mod+Shift+Period { move-column-to-monitor-right; }
    Mod+Ctrl+D { spawn "kanshictl" "switch" "desktop-dual"; }
    Mod+Ctrl+S { spawn "kanshictl" "switch" "desktop-single-dp3"; }
    Mod+Ctrl+M { spawn "toggle-display-mode"; }

    // Scroll through columns
    Mod+WheelScrollRight cooldown-ms=150 { focus-column-right; }
    Mod+WheelScrollLeft  cooldown-ms=150 { focus-column-left; }

    // Media / system
    XF86AudioRaiseVolume  allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
    XF86AudioLowerVolume  allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
    XF86AudioMute         allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
    F6  allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
    F5  allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
    F4  allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
    XF86AudioPlay  { spawn "playerctl" "play-pause"; }
    XF86AudioNext  { spawn "playerctl" "next"; }
    XF86AudioPrev  { spawn "playerctl" "previous"; }
    XF86MonBrightnessUp   { spawn "brightnessctl" "set" "+5%"; }
    XF86MonBrightnessDown { spawn "brightnessctl" "set" "5%-"; }

    // Screenshot
    Print { screenshot; }
    Ctrl+Print { screenshot-screen; }
    Alt+Print  { screenshot-window; }

    // Overview / help
    Mod+O     { toggle-overview; }
    Mod+Slash { show-hotkey-overlay; }

    // Session
    Mod+Escape { spawn "hyprlock"; }
    Mod+Shift+E { quit; }
    Mod+Shift+P { power-off-monitors; }
}
''
