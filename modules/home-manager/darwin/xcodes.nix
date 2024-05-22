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
    enableAria = mkOption {
      type = types.bool;
      default = true;
      description = "Use aria2 to download Xcode archives.";
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
      ++ lib.optionals cfg.enableAria [aria];

    home.activation.xcodes = lib.hm.dag.entryAfter ["writeBoundary"] (''

        export PATH="${lib.makeBinPath (with pkgs; [xcodes] ++ lib.optionals cfg.enableAria [aria])}:$PATH"

      ''
      + lib.concatMapStringsSep "\n" (
        version: ''
          xcodes install \
            --empty-trash \
            --no-superuser \
            --directory "${config.home.homeDirectory}/Applications" "${version}"
        ''
      )
      cfg.versions
      + ''

        xcodes select --directory "${config.home.homeDirectory}/Applications" "${cfg.active}"

      ''
      + ''

      '');
  };
}
