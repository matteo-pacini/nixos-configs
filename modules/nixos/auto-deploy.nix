{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.custom.autoDeploy;
in
{
  imports = [ inputs.comin.nixosModules.comin ];

  options.custom.autoDeploy = {
    enable = lib.mkEnableOption "comin pull deployments of the CI-gated `deploy` branch, staged with switch-to-configuration boot";
    telegramEnvFile = lib.mkOption {
      type = lib.types.str;
      description = "Env file with BOT_TOKEN and CHANNEL_ID for telegram-notify.";
    };
    telegramPrefix = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Text prepended to every Telegram message sent by the deploy hook.";
    };
    notifyStaged = lib.mkEnableOption "Telegram messages for staged deployments, and a daily reminder once a reboot has been pending for over 7 days";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.comin = {
          enable = true;
          # Prometheus metrics; nothing scrapes them yet, so keep them off the LAN.
          exporter.listen_address = "127.0.0.1";
          remotes = [
            {
              name = "origin";
              url = "https://github.com/matteo-pacini/nixos-configs.git";
              branches.main = {
                name = "deploy";
                operation = "boot";
              };
            }
          ];
          postDeploymentCommand = import ../shared/comin-hook.nix {
            inherit pkgs;
            inherit (cfg) telegramEnvFile telegramPrefix notifyStaged;
          };
        };
      }
      (lib.mkIf cfg.notifyStaged {
        systemd.services.comin-reboot-reminder = {
          description = "Remind about a comin deployment staged for over 7 days";
          environment = {
            TELEGRAM_ENV_FILE = cfg.telegramEnvFile;
            TELEGRAM_PREFIX = cfg.telegramPrefix;
          };
          serviceConfig.Type = "oneshot";
          script = ''
            profile=/nix/var/nix/profiles/system-profiles/comin
            [[ -e "$profile" ]] || exit 0
            [[ "$(readlink -f /run/booted-system)" != "$(readlink -f "$profile")" ]] || exit 0
            # The generation link (comin-N-link) is created when comin stages it.
            link="$(dirname "$profile")/$(readlink "$profile")"
            days=$(( ($(date +%s) - $(stat -c %Y "$link")) / 86400 ))
            if (( days >= 7 )); then
              ${pkgs.telegram-notify}/bin/telegram-notify \
                "⏰ @matteopacini a deployment has been staged for $days days, reboot pending"
            fi
          '';
        };
        systemd.timers.comin-reboot-reminder = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "09:00";
            Persistent = true;
          };
        };
      })
    ]
  );
}
