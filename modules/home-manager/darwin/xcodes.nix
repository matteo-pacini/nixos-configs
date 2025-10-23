{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.programs.xcodes;
  xcodesDir = "${config.home.homeDirectory}/Applications";

  # Setup PATH with required tools
  pathSetup = ''
    export PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          xcodes
          nawk
        ]
      )
    }:$PATH"
  '';

  # Update xcodes index to fetch latest available versions
  updateScript = ''
    echo "Updating Xcode versions index..."
    xcodes update 2>&1 > /dev/null
  '';

  # Install each requested Xcode version
  installScript = lib.concatMapStringsSep "\n" (version: ''
    echo "Installing Xcode ${version}..."
    xcodes install \
      --empty-trash \
      --no-superuser \
      --directory "${xcodesDir}" "${version}"
  '') cfg.versions;

  # Set the active Xcode version
  selectScript = ''
    echo "Setting active Xcode to ${cfg.active}..."
    xcodes select --directory "${xcodesDir}" "${cfg.active}"
  '';

  # Remove Xcode versions not in the requested list
  cleanupScript = ''
    echo "Cleaning up unrequested Xcode versions..."
    REQUESTED_VERSIONS="${concatStringsSep "\n" cfg.versions}"
    INSTALLED_VERSIONS="$(NO_COLOR=1 xcodes installed --directory "${xcodesDir}" | nawk -F ' \\(' '{print $1}')"

    TO_REMOVE="$(comm -23 <(echo "$INSTALLED_VERSIONS" | sort) <(echo "$REQUESTED_VERSIONS" | sort))"

    if [ -z "$TO_REMOVE" ]; then
      echo "No Xcodes to remove."
      exit 0
    fi

    while IFS= read -r version; do
      echo "Removing Xcode $version..."
      xcodes uninstall --empty-trash \
        --directory "${xcodesDir}" "$version"
    done <<< "$TO_REMOVE"
  '';
in
{
  options.programs.xcodes = {
    enable = mkEnableOption "Manages multiple Xcode installations on macOS";
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

    home.packages = with pkgs; [
      xcodes
    ];

    home.activation.xcodes = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      pathSetup + "\n" + updateScript + "\n" + installScript + "\n" + selectScript + "\n" + cleanupScript
    );
  };
}
