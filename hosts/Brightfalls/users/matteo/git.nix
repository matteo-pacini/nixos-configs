{
  pkgs,
  lib,
  isVM,
  config,
  ...
}:
let
  codeCommand = "${pkgs.lib.getExe config.programs.vscode.package}";
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
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
        identitiesOnly = true;
      };
      "nexus" = lib.mkIf (!isVM) {
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
    settings = {
      user = {
        name = "Matteo Pacini";
        email = "m+github@matteopacini.me";
      };
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
