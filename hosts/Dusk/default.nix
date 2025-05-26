{ pkgs, ... }:
{
  imports = [
    ./fonts.nix
    ./system.nix
  ];

  system.primaryUser = "matteo";

  nixpkgs.config.allowUnfree = true;

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "matteo" ];
    };
  };

  environment.systemPackages = [ ];

  users.users."matteo" = {
    home = "/Users/matteo";
  };

  programs.zsh.enable = true;

  system.stateVersion = 4;

  nixpkgs.hostPlatform = "x86_64-darwin";
}
