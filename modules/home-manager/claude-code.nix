{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.claude-code;

  # Wraps ccstatusline so a herdr pane also gets the model/effort label and a
  # context-usage token in its sidebar. No-ops outside herdr.
  statusLine = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./claude-code/herdr-statusline.sh;
  };

  baseSettings = {
    # Empty strings disable commit Co-Authored-By trailers and PR-body
    # attribution at the harness level (replaces deprecated includeCoAuthoredBy).
    attribution = {
      commit = "";
      pr = "";
    };
    statusLine = {
      type = "command";
      # Relies on nodejs being on claude's PATH (set in overlays/shared.nix).
      command = lib.getExe statusLine;
      padding = 0;
      refreshInterval = 10;
    };
  };
in
{
  options.custom.claude-code = {
    enable = lib.mkEnableOption "Claude Code with managed settings.json, ccstatusline, and CLAUDE.md";

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Extra keys merged into ~/.claude/settings.json on top of the base
        settings (attribution + statusLine). Use this for per-host overrides
        like permissions.allow, enabledPlugins, effortLevel, etc.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # nodejs is NOT installed user-wide — it's bundled onto claude's wrapped
    # PATH via overlays/shared.nix (needed by the npx-based statusLine).
    home.packages = [ pkgs.claude-code ];

    home.file.".config/ccstatusline/settings.json".source = ./claude-code/ccstatusline.json;

    # Copied (not symlinked) into place: Claude Code writes to this file at
    # runtime (/model, /config, effort), which errors on a read-only store
    # symlink. Each activation clobbers runtime edits — declared state wins.
    home.activation.claudeSettings =
      let
        settingsFile = pkgs.writeText "claude-settings.json" (
          builtins.toJSON (baseSettings // cfg.extraSettings)
        );
      in
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p "$HOME/.claude"
        run install -m 644 "${settingsFile}" "$HOME/.claude/settings.json"
      '';

    # Vendored global instruction doc for Claude Code.
    home.file.".claude/CLAUDE.md".source = ./claude-code/CLAUDE.md;
  };
}
