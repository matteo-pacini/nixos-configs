{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: let
  passbolt = pkgs.stdenv.mkDerivation rec {
    version = "4.7.0";
    name = "passbolt-${version}";
    addonId = "passbolt@passbolt.com";

    src = pkgs.fetchurl {
      url = "https://addons.mozilla.org/firefox/downloads/file/4280147/passbolt-4.7.0.xpi";
      hash = "sha256-mEXxapAIC/GKdQHGaZi8YQKGlLDsRnMoMTnRy1VaA2Y=";
    };

    buildCommand = ''
      dst="$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
      mkdir -p "$dst"
      install -v -m644 "$src" "$dst/${addonId}.xpi"
    '';
  };
in {
  imports = [
    ../../../shared/home-manager/firefox.nix
  ];

  # Append passbolt to the list of extensions
  programs.firefox.profiles.default.extensions = [
    passbolt
  ];
}
