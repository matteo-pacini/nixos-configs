{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.codex;

  herdrReport = pkgs.writeShellApplication {
    name = "herdr-codex-report";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
    ];
    text = builtins.readFile ./codex/herdr-report.sh;
  };

  # Bare command name, not a store path: Codex asks the user to trust each
  # hook by a hash of its definition, so the string must survive rebuilds.
  herdrHook = {
    type = "command";
    command = "herdr-codex-report";
    timeout = 10;
  };
in
{
  options.custom.codex.enable = lib.mkEnableOption "Codex CLI with the shared instruction doc as global AGENTS.md";

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        programs.codex = {
          enable = true;
          # Same tool-neutral doc claude-code ships as CLAUDE.md and opencode as
          # AGENTS.md; lands in ~/.codex/AGENTS.md. Auth state (auth.json/Keychain)
          # is runtime-managed by `codex login`, deliberately not managed here.
          context = ./claude-code/CLAUDE.md;
        };
      }

      (lib.mkIf config.custom.herdr.enable {
        home.packages = [ herdrReport ];

        # Merged in rather than owned: `herdr integration install` writes its
        # own hooks to this file, and Codex records trust state in
        # config.toml, so neither can be a read-only store symlink. Codex only
        # runs hooks with `[features] hooks = true`, which herdr's install sets.
        home.activation.codexHerdrHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          hooks="$HOME/.codex/hooks.json"
          run mkdir -p "$HOME/.codex"
          current=$(cat "$hooks" 2>/dev/null || true)
          tmp=$(mktemp)
          printf '%s' "''${current:-"{}"}" | ${lib.getExe pkgs.jq} --argjson hook '${builtins.toJSON herdrHook}' '
            reduce ("Stop", "PostToolUse") as $event (.;
              .hooks[$event] = [
                (.hooks[$event] // [])[]
                | .hooks |= map(select(.command != $hook.command))
                | select(.hooks != [])
              ] + [{hooks: [$hook]}])
          ' > "$tmp" && run mv "$tmp" "$hooks"
          rm -f "$tmp"
        '';
      })
    ]
  );
}
