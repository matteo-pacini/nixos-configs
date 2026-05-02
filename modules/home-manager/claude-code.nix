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

    # CLAUDE.md is assembled from numbered fragments so each section can be
    # edited in isolation. Order matches the structure documented in the repo's
    # root CLAUDE.md: role/tone → RTK reference → workflow → git → non-negotiables.
    home.file.".claude/CLAUDE.md".text = lib.concatStringsSep "\n" [
      (builtins.readFile ./claude-code/claude-md/01-role-tone.md)
      "@RTK.md\n"
      (builtins.readFile ./claude-code/claude-md/02-working-on-code.md)
      (builtins.readFile ./claude-code/claude-md/03-git.md)
      (builtins.readFile ./claude-code/claude-md/04-non-negotiables.md)
    ];
    home.file.".claude/RTK.md".source = ./claude-code/RTK.md;
  };
}
