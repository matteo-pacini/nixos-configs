{ inputs }:
final: prev: rec {
  unstable = import inputs.nixpkgs-unstable {
    inherit (final) system;
    config.allowUnfree = true;
  };

  reshade-steam-proton = prev.callPackage ./packages/reshade-steam-proton.nix { };
  nzbhydra2 = unstable.nzbhydra2;
}
