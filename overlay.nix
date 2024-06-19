{ inputs }:
final: prev: rec {
  unstable = import inputs.nixpkgs-unstable {
    inherit (final) system;
    config.allowUnfree = true;
  };

  unstable-mesa = unstable.mesa;
  unstable-steam = unstable.steam;

  _thisFlakePkgs = import ./packages {
    stdenv = prev.stdenv;
    pkgs = prev;
  };

  firefox-app = _thisFlakePkgs.firefox-app;
  needle = _thisFlakePkgs.needle;
  reshade-steam-proton = _thisFlakePkgs.reshade-steam-proton;
  swiftlint = _thisFlakePkgs.swiftlint;
  zed-app = _thisFlakePkgs.zed-app;
}
