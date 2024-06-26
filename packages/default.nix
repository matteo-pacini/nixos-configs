{ pkgs, stdenv }:
{
  reshade-steam-proton = pkgs.callPackage ./reshade-steam-proton.nix { };
}
