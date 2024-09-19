{ pkgs, ... }:
{
  imports = [
    ./fonts.nix
    ./system.nix
  ];

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

  services.nix-daemon.enable = true;

  environment.systemPackages = [ ];

  users.users."matteo" = {
    home = "/Users/matteo";
  };

  programs.zsh.enable = true;

  system.stateVersion = 4;

  nixpkgs.hostPlatform = "x86_64-darwin";
}
