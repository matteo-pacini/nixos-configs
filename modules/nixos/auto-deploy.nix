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
    branchOperation = "boot";
    modeFile = "/var/lib/comin-deploy/mode";
  };
in
{
  imports = [ inputs.comin.nixosModules.comin ];

  options.custom.autoDeploy = {
    enable = lib.mkEnableOption "comin pull deployments of the CI-gated `deploy` branch, staged with switch-to-configuration boot";
    confirm = lib.mkEnableOption "confirmed deployments: comin fetches and builds each new commit, then waits. `comin-deploy` (and the herdr Deploy panel's host menu) releases it with boot or switch, or sets a mode that does so on its own";
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
          deployConfirmer.mode = if cfg.confirm then "manual" else "without";
        };
      }
      (lib.mkIf cfg.confirm {
        environment.systemPackages = [ cominDeploy ];
        # wheel writes the mode file, through comin-deploy or the herdr panel.
        systemd.tmpfiles.rules = [ "d /var/lib/comin-deploy 0775 root wheel -" ];
        systemd.services.comin-deploy-auto = {
          description = "Deploy the generation comin is holding, if the comin-deploy mode says so";
          after = [ "comin.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${cominDeploy}/bin/comin-deploy auto";
          };
        };
        systemd.timers.comin-deploy-auto = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "2min";
            OnUnitActiveSec = "1min";
          };
        };
      })
    ]
  );
}
