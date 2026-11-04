{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.custom.autoDeploy;
  cominDeploy = import ../shared/comin-deploy.nix {
    inherit pkgs;
    comin = config.services.comin.package;
    branchOperation = "switch";
    modeFile = "/var/lib/comin-deploy/mode";
  };
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
    confirm = lib.mkEnableOption "confirmed deployments: comin fetches and builds each new commit, then waits. `comin-deploy` (and the herdr Deploy panel's host menu) releases it with switch, or sets a mode that does so on its own";
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
              branches.main.name = "deploy";
            }
          ];
          deployConfirmer.mode = if cfg.confirm then "manual" else "without";
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
      }
      (lib.mkIf cfg.confirm {
        environment.systemPackages = [ cominDeploy ];
        # admin writes the mode file, through comin-deploy or the herdr panel.
        system.activationScripts.postActivation.text = ''
          mkdir -p /var/lib/comin-deploy
          chgrp admin /var/lib/comin-deploy
          chmod 0775 /var/lib/comin-deploy
        '';
        launchd.daemons.comin-deploy-auto = {
          command = "${cominDeploy}/bin/comin-deploy auto";
          serviceConfig = {
            StartInterval = 60;
            StandardOutPath = "/var/log/comin-deploy.log";
            StandardErrorPath = "/var/log/comin-deploy.log";
          };
        };
      })
    ]
  );
}
