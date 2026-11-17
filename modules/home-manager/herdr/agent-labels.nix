# The terminal labels the workbench mods draw (agent.model, agent.context,
# agent.ask, ...), set from inside each agent: Claude Code's statusLine and
# hooks, Codex's hooks, opencode's plugin. Mods read them from `terminals()`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.herdr;

  # Sets the context, cache, model and effort labels the agent-list mod draws, then renders
  # ccstatusline as the plain statusLine does.
  claudeStatusLine = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [
      pkgs.jq
      pkgs.herdr-core
    ];
    text = builtins.readFile ./scripts/claude-statusline.sh;
  };

  # The statusLine command with claudeLimitsFile on: records the plan-limit
  # reading, then runs claude-statusline unchanged.
  claudeLimits = pkgs.writeShellApplication {
    name = "claude-statusline-limits";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      claudeStatusLine
    ];
    text = builtins.readFile ./scripts/claude-limits.sh;
  };

  # The same labels for Codex, from its hooks. On PATH under a fixed name, not
  # as a store path: Codex skips a hook until it's trusted (/hooks), and keys
  # that trust on the hook's definition, so a path that changes every rebuild
  # would need trusting again each time.
  codexLabels = pkgs.writeShellApplication {
    name = "herdr-codex-labels";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.herdr-core
      pkgs.jq
    ];
    text = builtins.readFile ./scripts/codex-labels.sh;
  };

  # Sets and clears `agent.ask`, what a waiting agent asks, from Claude Code's
  # and Codex's hooks (the Claude ones are in core.nix), as a terminal label
  # mods can read. On PATH under a fixed name for the same reason as
  # herdr-codex-labels.
  agentAsk = pkgs.writeShellApplication {
    name = "herdr-agent-ask";
    runtimeInputs = [
      pkgs.herdr-core
      pkgs.jq
    ];
    text = builtins.readFile ./scripts/agent-ask.sh;
  };
in
{
  options.custom.herdr.workbench.claudeLimitsFile.enable = lib.mkEnableOption ''
    recording Claude Code's plan-limit reading (the weekly and 5-hour
    `rate_limits` its status line receives) in
    `$XDG_RUNTIME_DIR/desk/claude-limits.json`, for a desktop shell to show.
    Takes effect with the workbench, whose status line writes it
  '';

  config = lib.mkIf (cfg.enable && cfg.workbench.enable) (
    lib.mkMerge [
      {
        home.packages = [ agentAsk ];

        custom.claude-code.extraSettings.statusLine = {
          type = "command";
          command = lib.getExe (
            if cfg.workbench.claudeLimitsFile.enable then claudeLimits else claudeStatusLine
          );
          padding = 0;
          refreshInterval = 10;
        };
      }

      (lib.mkIf config.custom.codex.enable {
        home.packages = [ codexLabels ];

        # hooks.json is Codex's own runtime file (it records trust beside it in
        # config.toml), so the hooks are merged in rather than the file owned.
        home.activation.herdrCodexHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          hooks="$HOME/.codex/hooks.json"
          run mkdir -p "$HOME/.codex"
          [ -f "$hooks" ] || echo '{"hooks":{}}' > "$hooks"
          tmp=$(mktemp)
          ${lib.getExe pkgs.jq} -f ${./scripts/codex-hooks.jq} "$hooks" > "$tmp" && run mv "$tmp" "$hooks"
          rm -f "$tmp"
          # Trusts these hooks as /hooks would, so a change to them doesn't stop
          # every Codex pane on "Hooks need review".
          run ${
            (pkgs.python3.withPackages (ps: [ ps.tomlkit ])).interpreter
          } ${./scripts/codex-trust-hooks.py} "$hooks" "$HOME/.codex/config.toml" herdr-codex-labels herdr-agent-ask
        '';
      })

      (lib.mkIf config.custom.opencode.enable {
        # Loaded from the plugins folder on start; sets the same labels from
        # opencode's session events.
        xdg.configFile."opencode/plugins/herdr-labels.js".source = ./scripts/opencode-labels.js;
      })
    ]
  );
}
