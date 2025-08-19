{ pkgs, flake, ... }:
{
  imports = [
    ./fonts.nix
    ./system.nix
  ];

  nixpkgs.config.allowUnfree = true;

  nix = {
    extraOptions = ''
      extra-platforms = x86_64-darwin aarch64-darwin
    '';
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "@admin"
      ];
      sandbox = "relaxed";
    };
  };

  environment.systemPackages = [ pkgs.nix-output-monitor ];

  users.users."matteo.pacini" = {
    home = "/Users/matteo.pacini";
  };

  system.primaryUser = "matteo.pacini";

  programs.zsh.enable = true;

  system.stateVersion = 6;

  nixpkgs.hostPlatform = "aarch64-darwin";

  system.configurationRevision = flake.rev or flake.dirtyRev or null;
}
