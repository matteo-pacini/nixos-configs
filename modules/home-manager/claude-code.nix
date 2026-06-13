{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.claude-code;

  # Shared base instruction generator (fragments live in ../agents-md/).
  agentsMd = import ./agents-md.nix { inherit lib; };

  # Effort levels supported by each model. Source of truth:
  # https://code.claude.com/docs/en/model-config#adjust-effort-level
  # Keys are values passed to `claude --model` — aliases auto-track the latest
  # version (https://code.claude.com/docs/en/model-config#model-aliases); pin
  # a full model ID (e.g. "claude-opus-4-8") when you need a specific version.
  # Empty list = model does not support --effort.
  modelEfforts = {
    opus = [
      "low"
      "medium"
      "high"
      "xhigh"
      "max"
    ];
    sonnet = [
      "low"
      "medium"
      "high"
      "max"
    ];
    haiku = [ ];
    # Pinned legacy versions (still available; not evergreen aliases).
    "claude-opus-4-7" = [
      "low"
      "medium"
      "high"
      "xhigh"
      "max"
    ];
    "claude-opus-4-6" = [
      "low"
      "medium"
      "high"
      "max"
    ];
  };

  # Maps each modelEfforts key to the slug used in the shell alias name
  # (`claude-<slug>` and `claude-<slug>-<effort>`). Pinned IDs get a compact
  # slug to avoid dash ambiguity with the effort suffix.
  modelAliasSlug = {
    opus = "opus";
    sonnet = "sonnet";
    haiku = "haiku";
    "claude-opus-4-7" = "opus47";
    "claude-opus-4-6" = "opus46";
  };

  # Whether each model supports the 1M-token context window. Source:
  # https://code.claude.com/docs/en/model-config#extended-context
  # When true, an additional set of `claude-<slug>-1m[-<effort>]` aliases is
  # generated, invoking the model with the `[1m]` suffix.
  model1mContext = {
    opus = true;
    sonnet = true;
    haiku = false;
    "claude-opus-4-7" = true;
    "claude-opus-4-6" = true;
  };

  # Generate `claude-<slug>[-<effort>]` for the default context window, plus
  # `claude-<slug>-1m[-<effort>]` when the model supports 1M context. The
  # model arg is single-quoted so zsh doesn't glob the `[1m]` brackets.
  claudeAliases = lib.listToAttrs (
    lib.concatMap (
      model:
      let
        slug = modelAliasSlug.${model};
        mkVariants =
          modelArg: slugSuffix:
          let
            baseCmd = "claude --model '${modelArg}'";
          in
          [ (lib.nameValuePair "claude-${slug}${slugSuffix}" baseCmd) ]
          ++ map (
            effort: lib.nameValuePair "claude-${slug}${slugSuffix}-${effort}" "${baseCmd} --effort ${effort}"
          ) modelEfforts.${model};
      in
      mkVariants model "" ++ lib.optionals model1mContext.${model} (mkVariants "${model}[1m]" "-1m")
    ) (lib.attrNames modelEfforts)
  );

  baseSettings = {
    # Empty strings disable commit Co-Authored-By trailers and PR-body
    # attribution at the harness level (replaces deprecated includeCoAuthoredBy).
    attribution = {
      commit = "";
      pr = "";
    };
    hooks = {
      PreToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "~/.claude/hooks/rtk-rewrite.sh";
            }
          ];
        }
      ];
    };
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
        settings (hooks + statusLine). Use this for per-host overrides
        like permissions.allow, enabledPlugins, effortLevel, etc.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # rtk is NOT installed user-wide — it's bundled onto claude's wrapped PATH
    # via overlays/shared.nix so it's only visible inside Claude sessions
    # (where ~/.claude/hooks/rtk-rewrite.sh consumes it). Same story for nodejs.
    home.packages = [ pkgs.claude-code ];

    # Aliases are set on zsh directly (every host enables it). Has no effect
    # on a host where programs.zsh.enable is false.
    programs.zsh.shellAliases = claudeAliases;

    home.file.".config/ccstatusline/settings.json".source = ./claude-code/ccstatusline.json;

    home.file.".claude/settings.json".text = builtins.toJSON (baseSettings // cfg.extraSettings);

    # CLAUDE.md is assembled from the shared fragment base (../agents-md/),
    # refined with the Claude-only specializations: the @RTK.md include (after
    # role/tone — Claude's hook rewrites invisibly, so it uses upstream's
    # auto-refreshed rtk-awareness doc) and the model-delegation tier (after
    # simplicity). Order matches the cascade documented in the root CLAUDE.md.
    home.file.".claude/CLAUDE.md".text = agentsMd.mkDoc {
      afterRoleTone = [ "@RTK.md\n" ];
      includeModelDelegation = true;
    };
    home.file.".claude/RTK.md".source = ./claude-code/RTK.md;

    home.file.".claude/hooks/rtk-rewrite.sh" = {
      source = ./claude-code/rtk-rewrite.sh;
      executable = true;
    };
  };
}
