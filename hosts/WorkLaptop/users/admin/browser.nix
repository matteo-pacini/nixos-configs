{ pkgs, ... }:
let
  passbolt = pkgs.stdenv.mkDerivation rec {
    version = "4.11.0";
    pname = "passbolt";
    addonId = "passbolt@passbolt.com";

    src = pkgs.fetchurl {
      url = "https://addons.mozilla.org/firefox/downloads/file/4428058/passbolt-${version}.xpi";
      hash = "sha256-JT1osJocDttB8/YF0WYXZguvyI6v5wr8LUHc2AhF6XM=";
    };

    buildCommand = ''
      dst="$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
      mkdir -p "$dst"
      install -v -m644 "$src" "$dst/${addonId}.xpi"
    '';
  };
in
{
  programs.firefox.profiles.default.extensions.packages = [ passbolt ];

  # Enable Firefox customization module
  programs.firefox.customization = {
    enable = true;

    history.enable = false;

    # Enable search engines
    search = {
      nixPackages.enable = true;
      nixOptions.enable = true;
      kagi = {
        enable = true;
        setAsDefault = true;
      };
    };

    # Enable extensions
    extensions = {
      enable = true;
      ublock.enable = true;
      onepassword.enable = true;
      dracula.enable = true;
    };
  };

}
