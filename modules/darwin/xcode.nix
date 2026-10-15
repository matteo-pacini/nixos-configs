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

  # Removing an Xcode, or the CoreSimulator/MobileDevice updates that
  # -runFirstLaunch installs, would break a running Xcode or simulator, so
  # quit them first. Graceful only: an app still running after the grace
  # period (e.g. held by a save dialog) fails activation instead of losing
  # work. Skipped when xcode-select points at no Xcode (Command Line Tools,
  # or a deleted app): nothing to break, and no simctl to shut down with.
  quitScript = ''
    developerDir=$(/usr/bin/xcode-select -p 2>/dev/null || true)
    if [[ "$developerDir" == *.app/Contents/Developer && -x "$developerDir/usr/bin/simctl" ]]; then
      user=${config.system.primaryUser}
      uid=$(id -u "$user")
      asUser() { launchctl asuser "$uid" sudo -u "$user" "$@"; }
      waitFor=()
      if pgrep -xq launchd_sim; then
        echo "shutting down simulators..." >&2
        asUser "$developerDir/usr/bin/simctl" shutdown all || true
        waitFor+=(launchd_sim)
      fi
      for app in Xcode:com.apple.dt.Xcode Simulator:com.apple.iphonesimulator; do
        # Checked first: addressing an app that is not running launches it.
        pgrep -xq "''${app%%:*}" || continue
        echo "quitting ''${app%%:*}..." >&2
        asUser /usr/bin/osascript -e "with timeout of 30 seconds" \
          -e "quit app id \"''${app#*:}\"" -e "end timeout" || true
        waitFor+=("''${app%%:*}")
      done
      if (( ''${#waitFor[@]} > 0 )); then
        echo "waiting up to 60s for ''${waitFor[*]} to exit..." >&2
        for _ in $(seq 60); do
          running=()
          for proc in "''${waitFor[@]}"; do
            pgrep -xq "$proc" && running+=("$proc")
          done
          (( ''${#running[@]} > 0 )) || break
          sleep 1
        done
        if (( ''${#running[@]} > 0 )); then
          echo "error: still running: ''${running[*]}; quit them and re-run activation" >&2
          exit 1
        fi
      fi
    fi
  '';

  installScript =
    version:
    let
      xcodebuild = "${appPath version}/Contents/Developer/usr/bin/xcodebuild";
    in
    ''
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
          ${nixStore} --delete "$xip" >/dev/null 2>&1 || true
        )
      fi
    ''
    + lib.optionalString cfg.firstLaunch ''
      # Checked on every activation, not only after an install, so an
      # activation interrupted after the mv still finishes the setup next time.
      ${xcodebuild} -license check >/dev/null 2>&1 || ${xcodebuild} -license accept
      ${xcodebuild} -checkFirstLaunchStatus || ${xcodebuild} -runFirstLaunch
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
    firstLaunch = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Accept the license and run `xcodebuild -runFirstLaunch` as root after
        installing. When false, Xcode asks for both on first open instead.
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
      # Left behind only by an activation killed mid-install.
      rm -rf /private/var/tmp/xcode.*
      unlistedXcodes=()
      for app in /Applications/Xcode-*.app; do
        [[ -d "$app" ]] || continue
        case "$app" in
          ${lib.concatMapStringsSep " | " appPath cfg.versions}) ;;
          *) unlistedXcodes+=("$app") ;;
        esac
      done
      if (( ''${#unlistedXcodes[@]} > 0 )) ${
        lib.concatMapStrings (v: " || [[ ! -d ${appPath v} ]]") cfg.versions
      }; then
        ${quitScript}
      fi
      ${lib.concatMapStrings installScript cfg.versions}
      /usr/bin/xcode-select --switch ${appPath cfg.active}
      for app in "''${unlistedXcodes[@]}"; do
        echo "removing $app" >&2
        rm -rf "$app"
      done
    '';
  };
}
