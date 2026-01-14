{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.apcupsdMulti;

  # List of events from "man apccontrol"
  eventList = [
    "annoyme"
    "battattach"
    "battdetach"
    "changeme"
    "commfailure"
    "commok"
    "doreboot"
    "doshutdown"
    "emergency"
    "failing"
    "killpower"
    "loadlimit"
    "mainsback"
    "onbattery"
    "offbattery"
    "powerout"
    "remotedown"
    "runlimit"
    "timeout"
    "startselftest"
    "endselftest"
  ];

  shellCmdsForEventScript = eventname: commands: ''
    echo "#!${pkgs.runtimeShell}" > "$out/${eventname}"
    echo '${commands}' >> "$out/${eventname}"
    chmod a+x "$out/${eventname}"
  '';

  # Generate config and services for a single UPS
  mkUpsConfig =
    name: upsCfg:
    let
      eventToShellCmds =
        event:
        if builtins.hasAttr event upsCfg.hooks then
          (shellCmdsForEventScript event (builtins.getAttr event upsCfg.hooks))
        else
          "";

      scriptDir = pkgs.runCommand "apcupsd-${name}-scriptdir" { preferLocalBuild = true; } (
        ''
          mkdir "$out"
          cp -r ${pkgs.apcupsd}/etc/apcupsd/* "$out"/
          chmod u+w "$out"/*
          (cd "$out" && rm -f changeme commok commfailure onbattery offbattery)
          rm -f "$out/apcupsd.conf"
          sed -i -e "s|^SCRIPTDIR=.*|SCRIPTDIR=$out|" "$out/apccontrol"
        ''
        + lib.concatStringsSep "\n" (map eventToShellCmds eventList)
      );

      configFile = pkgs.writeText "apcupsd-${name}.conf" ''
        ## apcupsd.conf v1.1 ##
        # apcupsd complains if the first line is not like above.
        ${upsCfg.configText}
        NISPORT ${toString upsCfg.nisPort}
        SCRIPTDIR ${toString scriptDir}
      '';

      wrappedBinaries =
        pkgs.runCommand "apcupsd-${name}-wrapped-binaries"
          {
            preferLocalBuild = true;
            nativeBuildInputs = [ pkgs.makeWrapper ];
          }
          ''
            mkdir -p "$out/bin"
            for p in "${lib.getBin pkgs.apcupsd}/bin/"*; do
                bname=$(basename "$p")
                makeWrapper "$p" "$out/bin/${name}-$bname" --add-flags "-f ${configFile}"
            done
          '';
    in
    {
      inherit configFile scriptDir wrappedBinaries;
    };

  # Generate all UPS configurations
  upsConfigs = lib.mapAttrs mkUpsConfig (lib.filterAttrs (n: v: v.enable) cfg.upses);

  # UPS submodule options
  upsOptions =
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to enable monitoring for this UPS.";
        };

        configText = lib.mkOption {
          type = lib.types.lines;
          default = ''
            UPSTYPE usb
            NISIP 127.0.0.1
            BATTERYLEVEL 50
            MINUTES 5
          '';
          description = ''
            Contents of the apcupsd.conf for this UPS. Do not include NISPORT
            or SCRIPTDIR as they are managed automatically.
          '';
        };

        nisPort = lib.mkOption {
          type = lib.types.port;
          default = 3551;
          description = ''
            Network Information Server port for this UPS. Each UPS must have
            a unique port. Use this port with apcaccess to query this specific UPS.
          '';
        };

        hooks = lib.mkOption {
          default = { };
          type = lib.types.attrsOf lib.types.lines;
          example = {
            doshutdown = "# shell commands to notify that the computer is shutting down";
          };
          description = ''
            Event hooks for this UPS. See "man apccontrol" for the list of events.
          '';
        };

        requiresNetwork = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether this UPS requires network connectivity to communicate.
            When true, the service will wait for network-online.target before starting.
            Enable this for SNMP-based or network-connected UPS devices.
          '';
        };
      };
    };

in
{
  options.services.apcupsdMulti = {
    upses = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule upsOptions);
      default = { };
      description = ''
        Attribute set of UPS devices to monitor. Each attribute name becomes
        the UPS identifier used in service names and wrapper scripts.
      '';
      example = lib.literalExpression ''
        {
          rack-ups = {
            enable = true;
            nisPort = 3551;
            configText = '''
              UPSNAME rack-ups
              UPSCABLE ether
              UPSTYPE snmp
              DEVICE 192.168.10.43:161:APC:Nexus
            ''';
          };
        }
      '';
    };
  };

  config = lib.mkIf (upsConfigs != { }) {
    # Assertions for valid hook names
    assertions = lib.flatten (
      lib.mapAttrsToList (name: upsCfg: [
        {
          assertion = lib.all (x: lib.elem x eventList) (builtins.attrNames upsCfg.hooks);
          message = ''
            Invalid hook names for UPS "${name}".
            Current: ${toString (builtins.attrNames upsCfg.hooks)}
            Valid: ${toString eventList}
          '';
        }
      ]) (lib.filterAttrs (n: v: v.enable) cfg.upses)
    );

    # Provide access to wrapped apcaccess tools for each UPS
    environment.systemPackages = lib.mapAttrsToList (name: conf: conf.wrappedBinaries) upsConfigs;

    # Generate a systemd service for each UPS
    systemd.services = lib.mkMerge [
      # Main apcupsd services
      (lib.mapAttrs' (
        name: conf:
        let
          upsCfg = cfg.upses.${name};
        in
        lib.nameValuePair "apcupsd-${name}" {
          description = "APC UPS Daemon (${name})";
          wantedBy = [ "multi-user.target" ];
          wants = lib.optionals upsCfg.requiresNetwork [ "network-online.target" ];
          after = lib.optionals upsCfg.requiresNetwork [ "network-online.target" ];
          preStart = "mkdir -p /run/apcupsd";
          serviceConfig = {
            ExecStart = "${pkgs.apcupsd}/bin/apcupsd -b -f ${conf.configFile} -d1";
            TimeoutStopSec = 5;
          };
          unitConfig.Documentation = "man:apcupsd(8)";
        }
      ) upsConfigs)

      # Killpower services for each UPS
      (lib.mapAttrs' (
        name: conf:
        lib.nameValuePair "apcupsd-${name}-killpower" {
          description = "APC UPS Kill Power (${name})";
          after = [ "shutdown.target" ];
          before = [ "final.target" ];
          wantedBy = [ "shutdown.target" ];
          unitConfig = {
            ConditionPathExists = "/run/apcupsd/${name}-powerfail";
            DefaultDependencies = "no";
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.apcupsd}/bin/apcupsd --killpower -f ${conf.configFile}";
            TimeoutSec = "infinity";
            StandardOutput = "tty";
            RemainAfterExit = "yes";
          };
        }
      ) upsConfigs)
    ];
  };
}
