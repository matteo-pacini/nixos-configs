{ pkgs, ... }:
{
  programs.zsh.enable = true;

  programs.command-not-found.enable = true;

  users.groups.poccelli = { };

  users.users = {
    "matteo" = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "media"
        "downloads"
        "poccelli"
      ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIID8wJBTqQWKLy0RxQDuw8PAvD/KwYxSBcWHS434E3ar NightSprings"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDL/dVnxSvd+NanEktj7P/XvBigagDGArj+EAc9Fj02/ WorkLaptop"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEDKbjllwk/2outyoF+hB1SrDmQD7X1ywrt17hvL5w6p BrightFalls"
      ];
    };
    "debora" = {
      isNormalUser = true;
      extraGroups = [
        "poccelli"
      ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE6nOm/5SEJUywMWrIH+afYX5vduEJMkfF+7y5Ue9FUY debora@CauldronLake"
      ];
    };
    "fabrizio" = {
      isNormalUser = true;
      shell = pkgs.zsh;
    };
  };
}
