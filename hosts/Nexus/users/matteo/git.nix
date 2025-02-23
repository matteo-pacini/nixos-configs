{ pkgs, ... }:
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
    # package = pkgs.gitAndTools.gitFull;
    userName = "Matteo Pacini";
    userEmail = "m+github@matteopacini.me";
    extraConfig = {
      init.defaultBranch = "master";
      core.sshCommand = "ssh -i ~/.ssh/github";
    };
  };
}
