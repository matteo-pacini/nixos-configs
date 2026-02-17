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
    };
    github = {
      enable = lib.mkEnableOption "GitHub SSH host block";
      identityFile = lib.mkOption {
        type = lib.types.str;
        default = "~/.ssh/github";
        description = "Path to GitHub identity file";
      };
    };
    extraMatchBlocks = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      description = "Additional SSH match blocks";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        matchBlocks."*" = {
          forwardAgent = false;
          addKeysToAgent = cfg.addKeysToAgent;
          compression = true;
          serverAliveInterval = 0;
          serverAliveCountMax = 3;
          hashKnownHosts = false;
          userKnownHostsFile = "~/.ssh/known_hosts";
          controlMaster = "no";
          controlPath = "~/.ssh/master-%r@%n:%p";
          controlPersist = "no";
          identitiesOnly = cfg.identitiesOnly;
        };
      };
    }
    (lib.mkIf (cfg.extraConfig != "") {
      programs.ssh.extraConfig = cfg.extraConfig;
    })
    (lib.mkIf cfg.nexus.enable {
      programs.ssh.matchBlocks."nexus" = {
        extraOptions = {
          HostName = "nexus.home.internal";
          User = "matteo";
          IdentityFile = "~/.ssh/nexus";
          Port = "1788";
        };
      };
    })
    (lib.mkIf cfg.github.enable {
      programs.ssh.matchBlocks."github.com" = {
        extraOptions = {
          HostName = "github.com";
          User = "git";
          IdentityFile = cfg.github.identityFile;
        };
      };
    })
    (lib.mkIf (cfg.extraMatchBlocks != { }) {
      programs.ssh.matchBlocks = cfg.extraMatchBlocks;
    })
  ]);
}
