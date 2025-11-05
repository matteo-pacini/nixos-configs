{
  pkgs,
  inputs,
  flake,
  ...
}:
{
  imports = [
    ./fonts.nix
    ./system.nix
  ];

  nixpkgs.config.allowUnfree = true;

  nix = {
    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ]; # Enables use of `nix-shell -p ...` etc
    registry = {
      nixpkgs.flake = inputs.nixpkgs; # Make `nix shell` etc use pinned nixpkgs
    };
    extraOptions = ''
      extra-platforms = x86_64-darwin aarch64-darwin
    '';
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "matteo"
      ];
      sandbox = "relaxed";
    };
  };

  environment.systemPackages = [ pkgs.nix-output-monitor ];

  users.users."matteo" = {
    home = "/Users/matteo";
  };

  system.primaryUser = "matteo";

  programs.zsh.enable = true;

  system.stateVersion = 4;

  nixpkgs.hostPlatform = "aarch64-darwin";

  system.configurationRevision = flake.rev or flake.dirtyRev or null;
}
