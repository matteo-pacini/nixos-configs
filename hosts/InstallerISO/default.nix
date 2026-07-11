# Custom NixOS installer ISO (minimal) with:
#   - the private attic cache as substituter, netrc token BAKED IN
#   - disko on the PATH
#
# Local x86_64-linux builds only — never CI (the token bake needs --impure
# and a host that holds the decrypted netrc). Keep the resulting ISO private.
#
# Build (e.g. on BrightFalls):
#   sudo ATTIC_NETRC_FILE=/run/agenix/brightfalls/attic-netrc \
#     nix build --impure .#nixosConfigurations.InstallerISO.config.system.build.isoImage
#
{ inputs, ... }:
let
  netrcSrc = builtins.getEnv "ATTIC_NETRC_FILE";
in
{
  custom.nix-core = {
    enable = true;
    trustedUsers = [
      "root"
      "nixos"
    ];
    atticCache = {
      enable = true;
      netrcFile = "/etc/nix/netrc";
    };
  };

  # Token baked into the image; pure eval fails on purpose
  environment.etc."nix/netrc" = {
    text =
      if netrcSrc == "" then
        throw "InstallerISO bakes the attic token: set ATTIC_NETRC_FILE=<decrypted netrc path> and build with --impure"
      else
        builtins.readFile netrcSrc;
    mode = "0400";
  };

  environment.systemPackages = [
    inputs.disko.packages.x86_64-linux.disko
  ];

  # `ssh nexus` from the live installer (restore files from the pool)
  programs.ssh.extraConfig = ''
    Host nexus
      HostName nexus.home.internal
      User matteo
      Port 1788
  '';
}
