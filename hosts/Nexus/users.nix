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
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPo7MktJS6OQ1UDcXKXTcN3HPJm2jc6XDLvGJ3flYgTK matteo@BrightFalls"
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
