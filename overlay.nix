{ inputs }:
final: prev: rec {
  unstable = import inputs.nixpkgs-unstable {
    inherit (final) system;
    config.allowUnfree = true;
  };

  _thisFlakePkgs = import ./packages {
    stdenv = prev.stdenv;
    pkgs = prev;
  };

  reshade-steam-proton = _thisFlakePkgs.reshade-steam-proton;
  # Overwrite the nzbhydra2 package with the one from the flake
  # Until PR #325062 is merged
  nzbhydra2 = _thisFlakePkgs.nzbhydra2;
}
