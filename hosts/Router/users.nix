{ pkgs, ... }:
{
  programs.zsh.enable = true;

  programs.command-not-found.enable = true;

  users.users = {
    "matteo" = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
      ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [ ];
    };
  };
}
