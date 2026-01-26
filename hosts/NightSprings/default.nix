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

  ids.gids.nixbld = 30000;

  environment.systemPackages = [ pkgs.nix-output-monitor ];

  users.users."matteo" = {
    home = "/Users/matteo";
    # Required after home-manager commit a521eab added home.uid option.
    # The nix-darwin integration unconditionally accesses users.users.<name>.uid
    # which fails if not set. See: https://github.com/nix-community/home-manager/commit/a521eab
    uid = 501;
  };

  system.primaryUser = "matteo";

  programs.zsh.enable = true;

  system.stateVersion = 6;

  nixpkgs.hostPlatform = "aarch64-darwin";

  system.configurationRevision = flake.rev or flake.dirtyRev or null;
}
