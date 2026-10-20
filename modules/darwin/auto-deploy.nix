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
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Env file with BOT_TOKEN and CHANNEL_ID for telegram-notify. Null disables the post-deployment hook, so nothing is reported.";
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
      postDeploymentCommand = lib.mkIf (cfg.telegramEnvFile != null) (
        import ../shared/comin-hook.nix {
          inherit pkgs;
          inherit (cfg) telegramEnvFile telegramPrefix;
        }
      );
    };

    # comin runs `activate` in comin's own process group, and activation unloads
    # comin whenever its plist changes (any nixpkgs bump). launchd then kills
    # the whole group, so activation dies before the new plist is loaded and
    # comin stays down. Abandoning the group lets activation finish and reload it.
    launchd.daemons.comin.serviceConfig.AbandonProcessGroup = true;
  };
}
