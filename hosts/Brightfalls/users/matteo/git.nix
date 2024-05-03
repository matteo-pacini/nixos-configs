{
  config,
  pkgs,
  inputs,
  ...
}: {
  programs.git = {
    enable = true;
    package = pkgs.gitAndTools.gitFull;
    userName = "Matteo Pacini";
    userEmail = "matteo@codecraft.it";
  };
}
