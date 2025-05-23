{ config, pkgs, ... }:
let
  codeCommand = "${pkgs.lib.getExe config.programs.vscode.package}";
in
{
  programs.ssh = {
    enable = true;
    compression = true;
    extraConfig = ''
      AddKeysToAgent yes
      UseKeychain yes
      IdentitiesOnly yes
    '';
    matchBlocks = {
      "nexus" = {
        extraOptions = {
          HostName = "192.168.7.7";
          User = "matteo";
          IdentityFile = "~/.ssh/nexus";
          Port = "1788";
        };
      };
      "router" = {
        extraOptions = {
          HostName = "192.168.7.1";
          User = "matteo";
          IdentityFile = "~/.ssh/router";
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
    * ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOv/Mfpgg5EbZPnQGldoTHsYQWOt4cYUqVyZkUVOzv44
  '';

  programs.git = {
    enable = true;
    lfs.enable = true;
    # package = pkgs.gitAndTools.gitFull;
    userName = "Matteo Pacini";
    userEmail = "matteo.pacini@transreport.co.uk";
    extraConfig = {
      init.defaultBranch = "master";
      core.editor = "${codeCommand} --wait";
      diff.tool = "vscode";
      difftool.vscode.cmd = "${codeCommand} --wait --diff $LOCAL $REMOTE";
      merge.tool = "vscode";
      mergetool.vscode.cmd = "${codeCommand} --wait --merge $REMOTE $LOCAL $BASE $MERGED";
      core.sshCommand = "ssh -i ~/.ssh/github";
      commit.gpgsign = true;
      gpg.format = "ssh";
      gpg.ssh.allowedSignersFile = "~/.ssh/allowed_signers";
      user.signingkey = "~/.ssh/github.pub";
    };
    includes = [
      {
        contents = {
          user = {
            email = "m+github@matteopacini.me";
          };
        };
        condition = "gitdir:${config.home.homeDirectory}/Repositories/";
      }
    ];
  };
}
