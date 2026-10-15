{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.xcode;
  hashes = lib.importJSON ./xcode-versions.json;
  nixStore = "${config.nix.package}/bin/nix-store";

  # Store path of the version's .xip as a plain string. Dropping the string
  # context keeps the multi-GB archive out of the system closure, so neither
  # CI nor the host's store carry it; activation substitutes it from attic
  # only when that version still has to be installed.
  xipPath =
    version:
    builtins.unsafeDiscardStringContext
      (pkgs.requireFile {
        name = "Xcode-${version}.xip";
        hash = hashes.${version};
        message = "Run `nix run .#xcode-fetch -- ${version}` to download Xcode ${version} and push it to attic.";
      }).outPath;

  appPath = version: "/Applications/Xcode-${version}.app";

  installScript = version: ''
    if [[ ! -d ${appPath version} ]]; then
      echo "installing Xcode ${version}..." >&2
      (
        xip=${xipPath version}
        ${nixStore} --realise "$xip" >/dev/null
        # Same volume as /Applications, so the final mv is an atomic rename
        # and an interrupted extraction never leaves a half-installed app.
        tmp=$(mktemp -d /private/var/tmp/xcode.XXXXXX)
        trap 'rm -rf "$tmp"' EXIT
        cd "$tmp"
        /usr/bin/xip --expand "$xip"
        mv "$tmp"/Xcode*.app ${appPath version}
        ${nixStore} --delete "$xip" >/dev/null || true
      )
      ${appPath version}/Contents/Developer/usr/bin/xcodebuild -license accept
      ${appPath version}/Contents/Developer/usr/bin/xcodebuild -runFirstLaunch
    fi
  '';
in
{
  options.custom.xcode = {
    enable = lib.mkEnableOption "Xcode installs from .xip archives cached in attic";
    versions = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames hashes));
      description = ''
        Xcode versions to keep in /Applications as Xcode-<version>.app. Each
        must have an entry in xcode-versions.json, added by xcode-fetch. Any
        other Xcode-*.app in /Applications is removed.
      '';
    };
    active = lib.mkOption {
      type = lib.types.str;
      description = "Version selected with xcode-select.";
    };
    xipPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "Store paths of the .xip archives for `versions`; CI checks they are in attic.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.elem cfg.active cfg.versions;
        message = "custom.xcode.active must be one of custom.xcode.versions.";
      }
    ];

    custom.xcode.xipPaths = map xipPath cfg.versions;

    system.activationScripts.postActivation.text = ''
      echo "setting up Xcode..." >&2
      ${lib.concatMapStrings installScript cfg.versions}
      /usr/bin/xcode-select --switch ${appPath cfg.active}
      for app in /Applications/Xcode-*.app; do
        [[ -d "$app" ]] || continue
        case "$app" in
          ${lib.concatMapStringsSep " | " appPath cfg.versions}) ;;
          *)
            echo "removing $app" >&2
            rm -rf "$app"
            ;;
        esac
      done
    '';
  };
}
