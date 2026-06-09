{
  pkgs,
  inputs,
  flake,
  config,
  ...
}:
{
  imports = [
    ./system.nix
  ];

  custom.nix-core = {
    enable = true;
    trustedUsers = [
      "@admin"
    ];
    # Substituter + auth for pulling from the private attic cache
    atticCache = {
      enable = true;
      netrcFile = config.age.secrets."worklaptop/attic-netrc".path;
    };
  };

  custom.fonts.enable = true;
  custom.nix-index.enable = true;

  environment.systemPackages = [ pkgs.nix-output-monitor ];

  users.users."matteo.pacini" = {
    home = "/Users/matteo.pacini";
    # Required after home-manager commit a521eab added home.uid option.
    # The nix-darwin integration unconditionally accesses users.users.<name>.uid
    # which fails if not set. See: https://github.com/nix-community/home-manager/commit/a521eab
    uid = 501;
  };

  system.primaryUser = "matteo.pacini";

  programs.zsh.enable = true;

  system.stateVersion = 6;

  nixpkgs.hostPlatform = "aarch64-darwin";

  system.configurationRevision = flake.rev or flake.dirtyRev or null;
}
