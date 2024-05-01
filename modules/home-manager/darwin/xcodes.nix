{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.xcodes;
in {
  options.programs.xcodes = {
    enable = mkEnableOption "Manages multiple Xcode installations on macOS";
    useAria = mkOption {
      type = types.bool;
      default = true;
      description = "Use aria2 for downloading Xcode archives.";
    };
    versions = mkOption {
      type = types.listOf types.str;
      default = ["15.3"];
      description = "List of Xcode versions to be installed.";
    };
    active = mkOption {
      type = types.str;
      default = "15.3";
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
        assertion = cfg.versions == [] || lib.elem cfg.active cfg.versions;
        message = "Active Xcode version must be one of the requested versions.";
      }
    ];

    home.packages = with pkgs;
      [
        xcodes
      ]
      ++ lib.optionals cfg.useAria [aria];

    home.activation.xcodes = lib.hm.dag.entryAfter ["writeBoundary"] ''

      export PATH="${lib.makeBinPath (with pkgs; [xcodes] ++ lib.optionals cfg.useAria [aria])}:$PATH"

      REQUIRED_XCODES="${concatStringsSep "\n" cfg.versions}"
      INSTALLED_XCODES=$(
        NO_COLOR=1 xcodes installed --directory "${config.home.homeDirectory}/Applications" | \
        grep -oE '^[^\(]*' || true
      )

      echo -e "Requested versions:\n$REQUIRED_XCODES"
      echo -e "Installed versions:\n$INSTALLED_XCODES"

      for version in $REQUIRED_XCODES; do
        if ! echo $INSTALLED_XCODES | grep -q "$version"; then
          echo "Installing Xcode $version..."
          xcodes install --directory "${config.home.homeDirectory}/Applications" "$version"
        else
          echo "Xcode $version is already installed"
        fi
      done

      for version in $INSTALLED_XCODES; do
        if ! echo $REQUIRED_XCODES | grep -q "$version"; then
          echo "Purging Xcode $version..."
          xcodes uninstall --directory "${config.home.homeDirectory}/Applications" "$version"
        fi
      done

      echo "Setting active Xcode to ${cfg.active}..."
      xcodes select --directory "${config.home.homeDirectory}/Applications" "${cfg.active}"
    '';
  };
}
