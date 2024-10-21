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
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJZ20/LITPU88Gg0u3ImBc6rr6uPKgRdRz2JWm6CWnV8 WorkLaptop"
      ];
    };
  };
}
