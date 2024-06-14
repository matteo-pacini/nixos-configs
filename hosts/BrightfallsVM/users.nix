{ pkgs, ... }:
{
  programs.zsh.enable = true;

  programs.command-not-found.enable = true;

  users.users."matteo" = {
    isNormalUser = true;
    initialPassword = "ziosasso";
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "docker"
    ];
    shell = pkgs.zsh;
  };
}
