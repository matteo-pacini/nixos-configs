{ config, pkgs, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "*" = {
        forwardAgent = false;
        addKeysToAgent = "yes";
        compression = true;
        serverAliveInterval = 0;
        serverAliveCountMax = 3;
        hashKnownHosts = false;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        controlPersist = "no";
        identitiesOnly = true;
      };
      "nexus" = {
        extraOptions = {
          HostName = "nexus.home.internal";
          User = "matteo";
          IdentityFile = "~/.ssh/nexus";
          Port = "1788";
        };
      };
      "github.com" = {
        extraOptions = {
          HostName = "github.com";
          User = "git";
          IdentityFile = "~/.ssh/github";
        };
      };
    };
  };

  home.file.".ssh/allowed_signers".text = ''
    * ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDrJTfkpn4k43/HcSuhM71ciHXAwjMphCxZXRR3zLhPG
  '';

  programs.git = {
    enable = true;
    lfs.enable = true;
    # package = pkgs.gitAndTools.gitFull;
    settings = {
      user = {
        name = "Matteo Pacini";
        email = "m+github@matteopacini.me";
      };
      init.defaultBranch = "master";
      core.editor = "nvim";
      diff.tool = "nvimdiff";
      merge.tool = "nvimdiff";
      core.sshCommand = "ssh -i ~/.ssh/github";
      commit.gpgsign = true;
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
      user.signingkey = "~/.ssh/github.pub";
      push.autoSetupRemote = true;
    };
    includes = [
      {
        contents = {
          user = {
            email = "matteo.pacini@transreport.co.uk";
          };
        };
        condition = "gitdir:${config.home.homeDirectory}/Work/";
      }
    ];
  };
}
