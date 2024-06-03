{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
{
  programs.ssh = {
    enable = true;
    compression = true;
    extraConfig = ''
      AddKeysToAgent yes
      UseKeychain yes
      IdentitiesOnly yes
    '';
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    package = pkgs.gitAndTools.gitFull;
    userName = "Matteo Pacini";
    userEmail = "matteo.pacini@transreport.co.uk";
    extraConfig = {
      init.defaultBranch = "master";
      core.editor = "code --wait";
      diff.tool = "vscode";
      difftool.vscode.cmd = "code --wait --diff $LOCAL $REMOTE";
      merge.tool = "vscode";
      mergetool.vscode.cmd = "code --wait --merge $REMOTE $LOCAL $BASE $MERGED";
      core.sshCommand = "ssh -i ~/.ssh/github_work";
    };
    includes = [
      {
        contents = {
          user = {
            email = "matteo@codecraft.it";
          };
          core = {
            sshCommand = "ssh -i ~/.ssh/github";
          };
        };
        condition = "gitdir:${config.home.homeDirectory}/Repositories/";
      }
      {
        contents = {
          core.excludesfile = pkgs.writeText ".gitignore" ''
            .direnv
            .envrc
            nix/xcode.sh
          '';
        };
        condition = "gitdir:${config.home.homeDirectory}/Work/";
      }
    ];
  };
}
