{ config, pkgs, ... }:
let
  codeCommand = "${config.programs.vscode.package}/bin/${config.programs.vscode.package.meta.mainProgram}";
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
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    package = pkgs.gitAndTools.gitFull;
    userName = "Matteo Pacini";
    userEmail = "matteo.pacini@transreport.co.uk";
    extraConfig = {
      init.defaultBranch = "master";
      core.editor = "${codeCommand} --wait";
      diff.tool = "vscode";
      difftool.vscode.cmd = "${codeCommand} --wait --diff $LOCAL $REMOTE";
      merge.tool = "vscode";
      mergetool.vscode.cmd = "${codeCommand} --wait --merge $REMOTE $LOCAL $BASE $MERGED";
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
            nix
          '';
        };
        condition = "gitdir:${config.home.homeDirectory}/Work/";
      }
    ];
  };
}
