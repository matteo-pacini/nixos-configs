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
  imports = [ inputs.comin.darwinModules.comin ];

  options.custom.autoDeploy = {
    enable = lib.mkEnableOption "comin pull deployments of the CI-gated `deploy` branch";
    telegramEnvFile = lib.mkOption {
      type = lib.types.str;
      description = "Env file with BOT_TOKEN and CHANNEL_ID for telegram-notify.";
    };
    telegramPrefix = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Text prepended to every Telegram message sent by the deploy hook.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.comin = {
      enable = true;
      # Prometheus metrics; nothing scrapes them yet, so keep them off the LAN.
      exporter.listen_address = "127.0.0.1";
      remotes = [
        {
          name = "origin";
          url = "https://github.com/matteo-pacini/nixos-configs.git";
          branches.main.name = "deploy";
        }
      ];
      postDeploymentCommand = import ../shared/comin-hook.nix {
        inherit pkgs;
        inherit (cfg) telegramEnvFile telegramPrefix;
      };
    };
  };
}
