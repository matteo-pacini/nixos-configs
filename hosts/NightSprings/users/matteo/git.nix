{
  config,
  pkgs,
  inputs,
  ...
}: {
  programs.git = {
    enable = true;
    lfs.enable = true;
    package = pkgs.gitAndTools.gitFull;
    userName = "matteo-pacini";
    userEmail = "matteo@codecraft.it";
  };
}
