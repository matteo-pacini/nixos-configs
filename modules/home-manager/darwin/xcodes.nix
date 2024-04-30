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
    enable = mkEnableOption "Xcodes service to manage multiple Xcode installations on macOS";
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
    home.packages = with pkgs; [
      aria
      xcodes
    ];

    home.activation.xcodes = lib.hm.dag.entryAfter ["writeBoundary"] ''

      export PATH="${lib.makeBinPath (with pkgs; [xcodes aria])}:$PATH"

      REQUIRED_XCODES="${concatStringsSep "\n" cfg.versions}"
      INSTALLED_XCODES=$(xcodes installed | grep -oE '^[^\(]*' | sed 's/ (//g')

      echo -e "Requested versions:\n$REQUIRED_XCODES"
      echo -e "Installed versions:\n$INSTALLED_XCODES"

      for version in $REQUIRED_XCODES; do
        if ! echo $INSTALLED_XCODES | grep -q "$version"; then
          echo "Installing Xcode $version"
          NO_COLOR=1 xcodes install "$version"
        else
          echo "Xcode $version is already installed"
        fi
      done

      for version in $INSTALLED_XCODES; do
        if ! echo $REQUIRED_XCODES | grep -q "$version"; then
          echo "Purging Xcode $version"
          NO_COLOR=1 xcodes uninstall "$version"
        fi
      done

      echo "Setting active Xcode to ${cfg.active}..."
      NO_COLOR=1 xcodes select "${cfg.active}"
    '';
  };
}
