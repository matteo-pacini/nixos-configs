{ config, pkgs, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    extraConfig = ''
      AddKeysToAgent yes
      UseKeychain yes
      IdentitiesOnly yes
    '';
    matchBlocks = {
      "*" = {
        forwardAgent = false;
        addKeysToAgent = "no";
        compression = true;
        serverAliveInterval = 0;
        serverAliveCountMax = 3;
        hashKnownHosts = false;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        controlPersist = "no";
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
    * ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+saZuvP72LcanCjTiXxPcGDBG7of8AJ2gxw/8o1rvI
  '';

  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      user = {
        name = "Matteo Pacini";
        email = "m+github@matteopacini.me";
      };
      alias = {
        clean-safe-dr = "clean -xdnf -e /.direnv/ -e /.envrc -e /nix/";
        clean-safe = "clean -xdf -e /.direnv/ -e /.envrc -e /nix/";
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
    };
    includes = [
      {
        contents = {
          core.excludesfile = pkgs.writeText ".gitignore" ''
            /.direnv/
            /.envrc
            /nix/
            /.android
            /.gradle
          '';
        };
        condition = "gitdir:${config.home.homeDirectory}/Repositories/blue-skies/";
      }
      {
        contents = {
          core.excludesfile = pkgs.writeText ".gitignore" ''
            /.direnv/
            /.envrc
            /nix/
          '';
        };
        condition = "gitdir:${config.home.homeDirectory}/Repositories/consumer-app-ios-v3/";
      }
    ];
  };
}
