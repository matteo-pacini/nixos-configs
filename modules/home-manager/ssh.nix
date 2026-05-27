{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.ssh;
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
    nexus = {
      enable = lib.mkEnableOption "Nexus host SSH block";
      tailscaleAliases = lib.mkEnableOption "Nexus Tailscale SSH aliases";
    };
    brightfalls = {
      enable = lib.mkEnableOption "BrightFalls host SSH blocks";
      tailscaleAliases = lib.mkEnableOption "BrightFalls Tailscale SSH aliases";
    };
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
      (lib.mkIf cfg.nexus.enable {
        programs.ssh.settings."nexus" = {
          HostName = "nexus.home.internal";
          User = "matteo";
          IdentityFile = "~/.ssh/nexus";
          Port = "1788";
        };
      })
      (lib.mkIf cfg.nexus.tailscaleAliases {
        programs.ssh.settings."nexus-ts" = {
          HostName = "nexus-ts.walrus-draconis.ts.net";
          User = "matteo";
          IdentityFile = "~/.ssh/nexus";
          Port = "1788";
        };
      })
      (lib.mkIf cfg.brightfalls.enable {
        programs.ssh.settings."brightfalls" = {
          HostName = "brightfalls.home.internal";
          User = "matteo";
          IdentityFile = "~/.ssh/brightfalls";
          Port = "1788";
        };
        programs.ssh.settings."brightfalls-stage1" = {
          HostName = "brightfalls.home.internal";
          User = "root";
          IdentityFile = "~/.ssh/brightfalls";
          Port = "2222";
        };
      })
      (lib.mkIf cfg.brightfalls.tailscaleAliases {
        programs.ssh.settings."brightfalls-ts" = {
          HostName = "brightfalls-ts.walrus-draconis.ts.net";
          User = "matteo";
          IdentityFile = "~/.ssh/brightfalls";
          Port = "1788";
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
