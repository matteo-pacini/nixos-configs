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
        "acme"
      ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIID8wJBTqQWKLy0RxQDuw8PAvD/KwYxSBcWHS434E3ar matteo@NightSprings"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFPfaTw8AYPvjul32mIt64juaOn8wjmlJoplWxCzCZhi matteo.pacini@WorkLaptop"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+kL6LcApeIKrvJQIsewG95Q2XyzrvUSyRvBC9Ip3y5 matteo@BrightFalls"
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
