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
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/374uncPCGejnyMojVd00DkPsECjggeZnMyrpAEKwO BrightFalls"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILGLYdoccZVwgzJMHC4xLtV64k/JePzJRlZ0LF8U/h31 NightSprings"
      ];
    };
  };
}
