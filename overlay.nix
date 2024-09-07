{ inputs }:
final: prev: rec {
  unstable = import inputs.nixpkgs-unstable {
    inherit (final) system;
    config.allowUnfree = true;
  };

  nzbhydra2 = unstable.nzbhydra2;
}
