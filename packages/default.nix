{ pkgs, stdenv }:
{
  needle = pkgs.callPackage ./needle { };

  firefox-app = pkgs.callPackage ./firefox-app.nix { };

  reshade-steam-proton = pkgs.callPackage ./reshade-steam-proton.nix { };

  swiftlint = pkgs.callPackage ./swiftlint.nix { };

  zed-app = pkgs.callPackage ./zed-app.nix { };
}
