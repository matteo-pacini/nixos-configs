{ config, lib, ... }:
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
  };
}
