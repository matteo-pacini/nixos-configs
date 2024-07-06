{ pkgs, stdenv }:
{
  reshade-steam-proton = pkgs.callPackage ./reshade-steam-proton.nix { };
  nzbhydra2 = pkgs.callPackage ./nzbhydra2.nix { };
}
