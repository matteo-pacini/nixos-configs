{ pkgs, ... }:
{
  programs.zsh.enable = true;

  programs.command-not-found.enable = true;

  users.users."matteo" = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "media"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIID8wJBTqQWKLy0RxQDuw8PAvD/KwYxSBcWHS434E3ar NightSprings"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDL/dVnxSvd+NanEktj7P/XvBigagDGArj+EAc9Fj02/ WorkLaptop"
    ];
  };
}
