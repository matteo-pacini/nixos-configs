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
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINm/ozPgRTmYmOVgkdNOw2deEOzBjoA4gGWLjWzrEC+u Pixel"
      ];
    };
    "debora" = {
      isNormalUser = true;
      extraGroups = [
        "poccelli"
      ];
      shell = pkgs.zsh;
    };
    "fabrizio" = {
      isNormalUser = true;
      shell = pkgs.zsh;
    };
  };
}
