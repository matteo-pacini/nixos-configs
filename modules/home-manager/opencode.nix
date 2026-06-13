{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = config.custom.opencode;

  # Kimi-specific anti-oscillation steering. Lives in the auto-loaded AGENTS.md
  # — which APPENDS after the model's base prompt for every agent — NOT in an
  # agent `prompt` field, which would REPLACE the ~95-line kimi.txt base prompt
  # (session/llm/request.ts:60). Targets K2.x's documented over-think /
  # simplicity-vs-robustness oscillation.
  kimiReasoningBudget = ''
    ## Reasoning Budget

    When a decision could go either way between brevity and edge-case safety,
    **choose brevity**. Stop self-critique loops once a workable answer is
    reached — do not re-litigate simplicity-vs-robustness trade-offs. If you
    have considered both sides once, commit and move on; the user can ask for
    the alternative if needed.
  '';

  # opencode's auto-loaded AGENTS.md: the shared fragment base (../agents-md/)
  # augmented with the per-profile Kimi steering. No RTK.md (the rtk.ts plugin
  # rewrites bash transparently; the awareness prose is Claude-hook-specific)
  # and no model-delegation (Claude model tiers).
  #
  # Placed at <OPENCODE_CONFIG_DIR>/AGENTS.md, this shadows ~/.claude/CLAUDE.md:
  # opencode's instruction loader takes the first existing file in
  # [<config>/AGENTS.md, ~/.claude/CLAUDE.md] and stops.
  sharedInstructions = (import ./agents-md.nix { inherit lib; }).mkDoc {
    afterSimplicity = [ kimiReasoningBudget ];
  };
  agentsMd = pkgs.writeText "opencode-AGENTS.md" sharedInstructions;

  # Per-profile, fully isolated config directory in the Nix store.
  #
  # opencode v1.16.2 tolerates a read-only OPENCODE_CONFIG_DIR: its npm
  # install guard skips non-writable dirs and the .gitignore writer
  # swallows PermissionDenied. File-based plugins are stat+read only.
  # Both `plugin/` and `plugins/` are scanned (glob `{plugin,plugins}/*.{ts,js}`),
  # so the store path can carry the rtk plugin directly.
  mkProfile =
    alias: p:
    let
      confDir = pkgs.runCommand "opencode-${alias}-confdir" { } ''
        mkdir -p "$out/plugin"
        install -m444 ${p.config} "$out/opencode.jsonc"
        install -m444 ${agentsMd} "$out/AGENTS.md"
        install -m444 ${./opencode/rtk.ts} "$out/plugin/rtk.ts"
      '';
    in
    pkgs.writeShellApplication {
      name = "opencode-${alias}";
      runtimeInputs = [
        pkgs.opencode
        pkgs.rtk
        pkgs.coreutils
      ];
      text = ''
        export OPENCODE_CONFIG_DIR=${confDir}
        export OPENCODE_CONFIG=${p.agents}
        root="$HOME/.local/share/opencode-${alias}"
        export XDG_DATA_HOME="$root/data"
        export XDG_STATE_HOME="$root/state"
        export XDG_CACHE_HOME="$root/cache"
        mkdir -p "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
      ''
      + lib.optionalString (cfg.openrouterKeyFile != null) ''
        if [ -r "${cfg.openrouterKeyFile}" ]; then
          set -a
          # shellcheck disable=SC1090,SC1091
          . "${cfg.openrouterKeyFile}"
          set +a
        else
          echo "opencode-${alias}: ${cfg.openrouterKeyFile} unreadable; run 'opencode auth login' or deploy the agenix secret" >&2
        fi
      ''
      + ''
        exec opencode "$@"
      '';
    };
in
{
  options.custom.opencode = {
    enable = lib.mkEnableOption "OpenCode profile launchers (opencode-<alias>)";

    openrouterKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      # Resolve the agenix-managed path of the shared `openrouter.env` secret
      # from the host (NixOS) config, rather than hardcoding /run/agenix/...;
      # falls back to null (→ rely on `opencode auth login`) on hosts that do
      # not define the secret.
      default = lib.attrByPath [
        "age"
        "secrets"
        "openrouter.env"
        "path"
      ] null osConfig;
      defaultText = lib.literalExpression ''osConfig.age.secrets."openrouter.env".path or null'';
      description = "Path to an env file defining OPENROUTER_API_KEY, sourced by every launcher. Defaults to the agenix path of the shared openrouter.env secret.";
    };

    profiles = lib.mkOption {
      default = { };
      description = "OpenCode profiles; attr name <alias> becomes the opencode-<alias> launcher.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            config = lib.mkOption {
              type = lib.types.path;
              description = "Profile opencode JSONC (models/providers/settings).";
            };
            agents = lib.mkOption {
              type = lib.types.path;
              description = "Profile agents JSONC (merged as the agent config layer).";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = lib.mapAttrsToList mkProfile cfg.profiles;
  };
}
