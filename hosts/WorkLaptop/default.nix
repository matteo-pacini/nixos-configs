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
    # Disk-pressured work SSD: stricter retention than the 30d default.
    gc.deleteOlderThan = "7d";
    trustedUsers = [
      "@admin"
    ];
    # Substituter + auth for pulling from the private attic cache
    atticCache = {
      enable = true;
      netrcFile = config.age.secrets."worklaptop/attic-netrc".path;
    };
  };

  # Free disk mid-build when it runs low (platform-agnostic daemon GC),
  # complementing the weekly scheduled GC on this space-constrained host.
  nix.settings = {
    min-free = 3221225472; # 3 GiB
    max-free = 10737418240; # 10 GiB
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
