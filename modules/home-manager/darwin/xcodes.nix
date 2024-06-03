{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.programs.xcodes;
in
{
  options.programs.xcodes = {
    enable = mkEnableOption "Manages multiple Xcode installations on macOS";
    enableAria = mkOption {
      type = types.bool;
      default = true;
      description = "Use aria2 to download Xcode archives.";
    };
    versions = mkOption {
      type = types.listOf types.str;
      default = [ "15.4" ];
      description = "List of Xcode versions to be installed.";
    };
    active = mkOption {
      type = types.str;
      default = "15.4";
      description = "Active Xcode version.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "Xcodes is only available on macOS.";
      }
      {
        assertion = cfg.versions == [ ] || lib.elem cfg.active cfg.versions;
        message = "Active Xcode version must be one of the requested versions.";
      }
    ];

    home.packages = with pkgs; [ xcodes ];

    home.activation.xcodes = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      ''

        export PATH="${
          lib.makeBinPath (
            with pkgs;
            [
              xcodes
              nawk
            ]
            ++ lib.optionals cfg.enableAria [ aria ]
          )
        }:$PATH"

        xcodes update 2>&1 > /dev/null

      ''
      + lib.concatMapStringsSep "\n" (version: ''
        xcodes install \
          --empty-trash \
          --no-superuser \
          --directory "${config.home.homeDirectory}/Applications" "${version}"
      '') cfg.versions
      + ''

        xcodes select --directory "${config.home.homeDirectory}/Applications" "${cfg.active}"

      ''
      + ''

        REQUESTED_VERSIONS="${concatStringsSep "\n" cfg.versions}"
        INSTALLED_VERSIONS="$(NO_COLOR=1 xcodes installed --directory "${config.home.homeDirectory}/Applications" | nawk -F ' \\(' '{print $1}')"

        TO_REMOVE="$(comm -23 <(echo "$INSTALLED_VERSIONS" | sort) <(echo "$REQUESTED_VERSIONS" | sort))"

        if [ -z "$TO_REMOVE" ]; then
          echo "No Xcodes to remove."
          exit 0
        fi

        while IFS= read -r version; do
          echo "Removing Xcode $version..."
          xcodes uninstall --empty-trash \
            --directory "${config.home.homeDirectory}/Applications" "$version"
        done <<< "$TO_REMOVE"

      ''
    );
  };
}
