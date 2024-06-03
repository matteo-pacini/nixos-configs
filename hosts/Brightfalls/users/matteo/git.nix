{
  config,
  pkgs,
  inputs,
  ...
}:
{
  programs.ssh = {
    enable = true;
    compression = true;
    extraConfig = ''
      IdentitiesOnly yes
    '';
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    package = pkgs.gitAndTools.gitFull;
    userName = "Matteo Pacini";
    userEmail = "matteo@codecraft.it";
    extraConfig = {
      init.defaultBranch = "master";
      core.editor = "code --wait";
      diff.tool = "vscode";
      difftool.vscode.cmd = "code --wait --diff $LOCAL $REMOTE";
      merge.tool = "vscode";
      mergetool.vscode.cmd = "code --wait --merge $REMOTE $LOCAL $BASE $MERGED";
      core.sshCommand = "ssh -i ~/.ssh/github";
    };
  };
}
