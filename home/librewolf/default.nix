{ lib, ... }:
{
  # Usability overrides layered on top of LibreWolf's hardened defaults.
  # These use defaultPref so the user can still override them in about:config.
  home.file.".librewolf/librewolf.overrides.cfg".text = ''
    // Fingerprinting resistance breaks web layouts and timezone detection
    defaultPref("privacy.resistFingerprinting", false);

    // Keep session state across restarts
    defaultPref("privacy.clearonshutdown.cookies", false);
    defaultPref("privacy.clearonshutdown.cache", false);

    // WebGL required for maps and interactive elements
    defaultPref("webgl.disabled", false);
    defaultPref("librewolf.webgl.prompt", false);

    // DRM for media playback
    defaultPref("media.eme.enabled", true);

    // Required for userChrome.css to take effect
    defaultPref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
  '';

  # Seed a fixed-path profile so apply-theme always knows where userChrome.css lives.
  # Written as a real writable file (not a nix store symlink) so LibreWolf can update it.
  home.activation.librewolfProfile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PROFILES="$HOME/.librewolf/profiles.ini"
    if [ ! -f "$PROFILES" ]; then
      $DRY_RUN_CMD mkdir -p "$HOME/.librewolf"
      $DRY_RUN_CMD tee "$PROFILES" > /dev/null << 'EOF'
[Profile0]
Name=default
IsRelative=1
Path=default
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF
    fi
  '';
}
