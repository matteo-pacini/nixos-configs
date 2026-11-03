{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.codex;
in
{
  options.custom.codex.enable = lib.mkEnableOption "Codex CLI with the shared instruction doc as global AGENTS.md";

  config = lib.mkIf cfg.enable {
    programs.codex = {
      enable = true;
      # Same tool-neutral doc claude-code ships as CLAUDE.md and opencode as
      # AGENTS.md; lands in ~/.codex/AGENTS.md. Auth state (auth.json/Keychain)
      # is runtime-managed by `codex login`, deliberately not managed here.
      context = ./claude-code/CLAUDE.md;
    };

    # Drops the hooks the legacy herdr TUI merged into hooks.json, and the
    # script one of them ran. Both were written at runtime, so Home Manager
    # never owned them, and Codex would fail on every event trying to run them.
    # Other hooks in the file are kept.
    home.activation.codexHerdrCleanup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      hooks="$HOME/.codex/hooks.json"
      if [ -f "$hooks" ]; then
        tmp=$(mktemp)
        ${lib.getExe pkgs.jq} '
          if has("hooks") then
            .hooks |= (
              with_entries(
                .value |= map(
                  .hooks |= map(select(
                    .command != "herdr-codex-report"
                    and (.command | test("herdr-agent-state\\.sh") | not)
                  ))
                  | select(.hooks != [])
                )
              )
              | with_entries(select(.value != []))
            )
          else . end
        ' "$hooks" > "$tmp" && run mv "$tmp" "$hooks"
        rm -f "$tmp"
      fi
      run rm -f "$HOME/.codex/herdr-agent-state.sh"
    '';
  };
}
