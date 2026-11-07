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
  config = lib.mkIf (cfg.enable && cfg.workbench.enable) (
    lib.mkMerge [
      {
        home.packages = [ agentAsk ];

        custom.claude-code.extraSettings.statusLine = {
          type = "command";
          command = lib.getExe claudeStatusLine;
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
          ${lib.getExe pkgs.jq} '
            .hooks //= {}
            | reduce (
                { command: "herdr-codex-labels", timeout: 10, events: ["SessionStart", "Stop", "PostToolUse"] },
                # Codex fires Interrupt when a prompt is denied, PreModelRequest
                # when the model is asked again after one. 3 s: Codex clamps an
                # Interrupt hook to that, and trusts the clamped definition.
                { command: "herdr-agent-ask", timeout: 3, events: ["PermissionRequest", "PostToolUse", "UserPromptSubmit", "Interrupt", "PreModelRequest", "Stop"] }
              ) as $hook (.;
                reduce $hook.events[] as $event (.;
                  .hooks[$event] = (
                    (.hooks[$event] // [])
                    | map(.hooks |= map(select(.command != $hook.command)) | select(.hooks != []))
                  ) + [{ hooks: [{ type: "command", command: $hook.command, timeout: $hook.timeout }] }]))
          ' "$hooks" > "$tmp" && run mv "$tmp" "$hooks"
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
