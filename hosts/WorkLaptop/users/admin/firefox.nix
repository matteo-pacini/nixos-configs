{ pkgs, ... }:
let
  passbolt = pkgs.stdenv.mkDerivation rec {
    version = "4.9.1";
    pname = "passbolt";
    addonId = "passbolt@passbolt.com";

    src = pkgs.fetchurl {
      url = "https://addons.mozilla.org/firefox/downloads/file/4325047/passbolt-4.9.1.xpi";
      hash = "sha256-QChZOB7sm+IFnl7mAD8vji0hUM8OO2E7UVACWJ4U9Qk=";
    };

    buildCommand = ''
      dst="$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
      mkdir -p "$dst"
      install -v -m644 "$src" "$dst/${addonId}.xpi"
    '';
  };
in
{
  imports = [ ../../../shared/home-manager/firefox.nix ];

  # Append passbolt to the list of extensions
  programs.firefox.profiles.default.extensions = [ passbolt ];
}
