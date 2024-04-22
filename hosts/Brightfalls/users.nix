{
  config,
  pkgs,
  ...
}: {
  programs.zsh.enable = true;

  programs.command-not-found.enable = true;

  users.users."matteo" = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "audio" "video" "input" "corectrl"];
    shell = pkgs.zsh;
  };
}
