{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.claude-code;
  baseSettings = {
    statusLine = {
      type = "command";
      # Relies on nodejs being on claude's PATH (set in overlays/shared.nix).
      command = "npx -y ccstatusline@latest";
      padding = 0;
      refreshInterval = 10;
    };
  };
in
{
  options.custom.claude-code = {
    enable = lib.mkEnableOption "Claude Code with managed settings.json, ccstatusline, CLAUDE.md, and bundled rtk";

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = ''
        Extra keys merged into ~/.claude/settings.json on top of the base
        settings (which only sets statusLine). Use this for per-host overrides
        like permissions.allow, enabledPlugins, effortLevel, etc.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # rtk is NOT installed user-wide — it's bundled onto claude's wrapped PATH
    # via overlays/shared.nix so it's only visible inside Claude sessions
    # (where ~/.claude/hooks/rtk-rewrite.sh consumes it). Same story for nodejs.
    home.packages = [ pkgs.claude-code ];

    home.file.".config/ccstatusline/settings.json".source = ./claude-code/ccstatusline.json;

    home.file.".claude/settings.json".text = builtins.toJSON (baseSettings // cfg.extraSettings);

    home.file.".claude/CLAUDE.md".source = ./claude-code/CLAUDE.md;
    home.file.".claude/RTK.md".source = ./claude-code/RTK.md;
  };
}
