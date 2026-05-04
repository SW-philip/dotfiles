{ config, pkgs, lib, inputs, ... }:

{
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;  # Use the system package
    systemd.enable = true;
    plugins = lib.mkForce [];

    extraConfig = ''
      debug {
        disable_logs = true
      }

      source = ~/.config/hypr/monitor.conf
      source = ~/.config/hypr/env.conf
      source = ~/.config/hypr/input.conf
      source = ~/.config/hypr/layout.conf
      source = ~/.config/hypr/decoration.conf
      source = ~/.config/hypr/animations.conf
      source = ~/.config/hypr/rules.conf
      source = ~/.config/hypr/binds.conf
      source = ~/.config/hypr/exec.conf
      source = ~/.config/hypr/workspaces.conf
    '';
  };

  xdg.configFile."hypr" = {
    source = ./.;
    recursive = true;
    force = true;
  };
  
  xdg.configFile."fuzzel/fuzzel.ini" = {
    source = ./fuzzel.ini;
  };
}
