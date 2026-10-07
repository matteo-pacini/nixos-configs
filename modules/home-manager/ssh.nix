{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.ssh;
  mesh = import ../../lib/ssh-mesh.nix;
  meshHostBlocks = name: h: user: {
    ${name} = {
      HostName = h.lan;
      User = user;
      IdentityFile = "~/.ssh/mesh";
      Port = toString h.port;
    };
    "${name}-ts" = {
      HostName = h.tailscale;
      User = user;
      IdentityFile = "~/.ssh/mesh";
      Port = toString h.port;
    };
  };
in
{
  options.custom.ssh = {
    enable = lib.mkEnableOption "SSH configuration";
    addKeysToAgent = lib.mkOption {
      type = lib.types.str;
      default = "no";
      description = "Whether to add keys to the SSH agent";
    };
    identitiesOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Only use identity files explicitly configured";
    };
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra SSH config lines";
    };
    mesh = {
      enable = lib.mkEnableOption "SSH mesh host blocks (<host>, <host>-ts) and daily certificate renewal";
      host = lib.mkOption {
        type = lib.types.enum (lib.attrNames mesh.hosts);
        description = "This host's name in lib/ssh-mesh.nix; selects which destinations get host blocks.";
      };
    };
    brightfalls.initrd = lib.mkEnableOption "BrightFalls initrd (LUKS unlock) SSH blocks, using ~/.ssh/brightfalls";
    github = {
      enable = lib.mkEnableOption "GitHub SSH host block";
      identityFile = lib.mkOption {
        type = lib.types.str;
        default = "~/.ssh/github";
        description = "Path to GitHub identity file";
      };
    };
    extraSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      description = "Additional SSH `programs.ssh.settings` blocks (directives written directly, no `extraOptions` wrapper).";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          settings."*" = {
            ForwardAgent = false;
            AddKeysToAgent = cfg.addKeysToAgent;
            Compression = true;
            ServerAliveInterval = 0;
            ServerAliveCountMax = 3;
            HashKnownHosts = false;
            UserKnownHostsFile = "~/.ssh/known_hosts";
            ControlMaster = "no";
            ControlPath = "~/.ssh/master-%r@%n:%p";
            ControlPersist = "no";
            IdentitiesOnly = cfg.identitiesOnly;
          };
        };
      }
      (lib.mkIf (cfg.extraConfig != "") {
        programs.ssh.extraConfig = cfg.extraConfig;
      })
      (lib.mkIf cfg.mesh.enable {
        programs.ssh.settings = lib.mkMerge (
          map (
            dest: meshHostBlocks mesh.hosts.${dest}.principal mesh.hosts.${dest} mesh.hosts.${dest}.user
          ) mesh.allow.${cfg.mesh.host}
          ++ [ (meshHostBlocks "mesh-ca" mesh.hosts.${mesh.signer} "sshca") ]
        );

        home.packages = [ pkgs.ssh-mesh-renew ];

        systemd.user.services.ssh-mesh-renew = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          Unit.Description = "Renew SSH mesh certificate";
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe pkgs.ssh-mesh-renew;
          };
        };
        systemd.user.timers.ssh-mesh-renew = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          Unit.Description = "Renew SSH mesh certificate";
          Timer = {
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
          Install.WantedBy = [ "timers.target" ];
        };

        launchd.agents.ssh-mesh-renew = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          enable = true;
          config = {
            ProgramArguments = [ (lib.getExe pkgs.ssh-mesh-renew) ];
            RunAtLoad = true;
            StartCalendarInterval = [
              {
                Hour = 12;
                Minute = 0;
              }
            ];
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/ssh-mesh-renew.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/ssh-mesh-renew.log";
          };
        };
      })
      (lib.mkIf cfg.brightfalls.initrd {
        programs.ssh.settings."brightfalls-stage1" = {
          HostName = "brightfalls.home.internal";
          User = "root";
          IdentityFile = "~/.ssh/brightfalls";
          Port = "2222";
        };
        programs.ssh.settings."brightfalls-ts-stage1" = {
          HostName = "brightfalls.home.internal";
          User = "root";
          IdentityFile = "~/.ssh/brightfalls";
          Port = "2222";
          ProxyJump = "nexus-ts";
        };
      })
      (lib.mkIf cfg.github.enable {
        programs.ssh.settings."github.com" = {
          HostName = "github.com";
          User = "git";
          IdentityFile = cfg.github.identityFile;
        };
      })
      (lib.mkIf (cfg.extraSettings != { }) {
        programs.ssh.settings = cfg.extraSettings;
      })
    ]
  );
}
