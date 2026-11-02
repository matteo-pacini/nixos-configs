{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.custom.hex;
  json = pkgs.formats.json { };

  shortcut = "control+option+space";
  model = "cohere_transcribe";
  # Replaces the whole Global mode on every activation, so add replacements
  # here rather than in Hex's Modes pane.
  settings."dictation_processing.default_mode" = {
    name = "Global";
    applications = [ ];
    browser_hosts = [ ];
    post_processing = {
      enabled = false;
      deadline_seconds = 30;
      model = null;
      variant = null;
      prompt = "Rewrite the transcript into clear, natural text while preserving the speaker's intended meaning.";
    };
    replacements = [
      {
        matched_phrase = "slash clear";
        output = "/clear";
      }
      {
        matched_phrase = "slash caveman";
        output = "/caveman";
      }
      {
        matched_phrase = "nix packages";
        output = "nixpkgs";
      }
    ];
    transformations = [ ];
  };

  # The macOS release tracks the hex flake input's version, so every host
  # runs the same Hex.
  darwinApp = pkgs.callPackage ../../packages/hex-darwin.nix {
    version = (builtins.fromTOML (builtins.readFile "${inputs.hex}/Cargo.toml")).package.version;
  };
  # A copy, not a store path or mac-app-util trampoline: the login item and
  # the Accessibility grant expect the app to stay at one path.
  darwinAppPath = "${config.home.homeDirectory}/Applications/Hex.app";
in
{
  # The upstream module only builds for x86_64-linux; importing it elsewhere
  # is harmless as long as programs.hex stays disabled there.
  imports = [ inputs.hex.homeManagerModules.hex ];

  options.custom.hex.enable = lib.mkEnableOption "Hex local voice dictation";

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        programs.hex = {
          enable = true;
          inherit shortcut model;
          installModel = true;
          autostart = true;
          # Linux only: macOS lacks the listener_control capability, and
          # `hex settings apply` rejects the whole file over one such key.
          settings = settings // {
            enable_on_launch = true;
          };
        };
      })
      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        # Nix owns the version; the in-app updater would swap the copy below.
        targets.darwin.defaults."anomaly.hex".DisableUpdates = true;

        home.activation.hexApp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          installed=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
            ${lib.escapeShellArg darwinAppPath}/Contents/Info.plist 2>/dev/null || true)
          if [[ "$installed" != ${lib.escapeShellArg darwinApp.version} ]]; then
            run rm -rf ${lib.escapeShellArg darwinAppPath}
            run mkdir -p "$(dirname ${lib.escapeShellArg darwinAppPath})"
            run cp -R ${darwinApp}/Applications/Hex.app ${lib.escapeShellArg darwinAppPath}
            # Store files are read-only; the next upgrade has to remove them.
            run chmod -R u+w ${lib.escapeShellArg darwinAppPath}
          fi
        '';

        # Writes ~/Library/Application Support/hex/settings.json when Hex is
        # stopped, or hands the settings to the running app.
        home.activation.hexSettings = lib.hm.dag.entryAfter [ "hexApp" ] ''
          if ! run ${darwinApp}/Applications/Hex.app/Contents/MacOS/hex settings apply ${
            json.generate "hex-settings.json" (
              {
                dictation_hotkey = shortcut;
                "transcription.model" = model;
              }
              // settings
            )
          }; then
            warnEcho "Hex didn't apply its settings; see the message above."
          fi
        '';

        launchd.agents.hex = {
          enable = true;
          config = {
            ProgramArguments = [
              "/usr/bin/open"
              "-a"
              darwinAppPath
            ];
            RunAtLoad = true;
          };
        };
      })
    ]
  );
}
