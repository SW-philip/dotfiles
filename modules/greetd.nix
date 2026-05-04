# modules/greetd.nix
{ pkgs, lib, config, ... }:
{
  options.greetd.greeting = lib.mkOption {
    type    = lib.types.str;
    default = "Welcome.";
  };

  config = {
    services.greetd = {
      enable = true;
      settings.default_session = {
        command = ''
          ${pkgs.tuigreet}/bin/tuigreet \
          --time \
          --remember \
          --remember-session \
          --greeting "${config.greetd.greeting}" \
          --asterisks \
          --asterisks-char "•" \
          --width 80 \
          --window-padding 1 \
          --container-padding 4 \
          --prompt-padding 1 \
          --greet-align center \
          --power-shutdown "systemctl poweroff" \
          --power-reboot "systemctl reboot" \
          --theme "background=#232136;border=#c4a7e7;text=#e0def4;prompt=#9ccfd8;time=#f6c177;action=#ea9a97;button=#eb6f92;container=#2a273f;input=#e0def4"'';
        user = "greeter";
      };
    };

    systemd.services."getty@tty1".enable  = false;
    systemd.services."autovt@tty1".enable = false;

    users.users.greeter = {
      isSystemUser = true;
      group = "greeter";
    };
    users.groups.greeter = {};
  };
}
