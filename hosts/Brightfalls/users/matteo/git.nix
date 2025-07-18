{ pkgs, config, ... }:
let
  codeCommand = "${pkgs.lib.getExe config.programs.vscode.package}";
in
{
  programs.ssh = {
    enable = true;
    compression = true;
    extraConfig = ''
      IdentitiesOnly yes
    '';
    matchBlocks = {
      "nexus" = {
        extraOptions = {
          HostName = "nexus";
          User = "matteo";
          IdentityFile = "~/.ssh/nexus";
          Port = "1788";
        };
      };
    };
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    # package = pkgs.gitAndTools.gitFull;
    userName = "Matteo Pacini";
    userEmail = "m+github@matteopacini.me";
    extraConfig = {
      init.defaultBranch = "master";
      core.editor = "${codeCommand} --wait";
      diff.tool = "vscode";
      difftool.vscode.cmd = "${codeCommand} --wait --diff $LOCAL $REMOTE";
      merge.tool = "vscode";
      mergetool.vscode.cmd = "${codeCommand} --wait --merge $REMOTE $LOCAL $BASE $MERGED";
      core.sshCommand = "ssh -i ~/.ssh/github";
    };
  };
}
