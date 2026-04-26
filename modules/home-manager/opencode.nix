{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.opencode;
in
{
  options.custom.opencode = {
    enable = lib.mkEnableOption "OpenCode configuration with agent definitions";
  };

  config = lib.mkIf cfg.enable {
    home.file.".config/opencode/opencode.json".text = builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      model = "openrouter/moonshotai/kimi-k2.6";
      agent = {
        build = {
          description = "Primary coding agent. Full file and bash access. Uses Kimi K2.6 — Tier A in April 2026 benchmarks, best value coding model at ~$0.30/run.";
          mode = "primary";
          model = "openrouter/moonshotai/kimi-k2.6";
          temperature = 0.2;
          max_iterations = 25;
        };
        plan = {
          description = "Planning and architecture agent. Read-only, no file writes. Uses Kimi K2.6 — same Tier A quality without the extra cost of thinking mode.";
          mode = "primary";
          model = "openrouter/moonshotai/kimi-k2.6";
          temperature = 0.3;
          max_iterations = 15;
          permission = {
            write = { "*" = "deny"; };
            edit = { "*" = "deny"; };
            bash = { "*" = "deny"; };
          };
        };
        explore = {
          description = "Lightweight codebase explorer. Read-only. Uses DeepSeek V4 Flash — $0.01/run, 1M context, cheapest useful model available.";
          mode = "subagent";
          model = "openrouter/deepseek/deepseek-v4-flash";
          temperature = 0.1;
          max_iterations = 10;
          permission = {
            write = { "*" = "deny"; };
            edit = { "*" = "deny"; };
            bash = { "*" = "deny"; };
            read = { "*" = "allow"; };
            glob = { "*" = "allow"; };
            grep = { "*" = "allow"; };
          };
        };
        review = {
          description = "Code review agent. Read-only. Uses Gemini 3 Flash — fast, 1M context, good at spotting issues.";
          mode = "subagent";
          model = "openrouter/google/gemini-3-flash-preview";
          temperature = 0.1;
          max_iterations = 10;
          permission = {
            write = { "*" = "deny"; };
            edit = { "*" = "deny"; };
            bash = { "*" = "deny"; };
            read = { "*" = "allow"; };
            glob = { "*" = "allow"; };
            grep = { "*" = "allow"; };
          };
        };
        debug = {
          description = "Debug agent. Can read files and run bash commands but cannot edit. Uses Kimi K2.6 for reliable reasoning.";
          mode = "subagent";
          model = "openrouter/moonshotai/kimi-k2.6";
          temperature = 0.1;
          max_iterations = 15;
          permission = {
            write = { "*" = "deny"; };
            edit = { "*" = "deny"; };
            bash = { "*" = "allow"; };
            read = { "*" = "allow"; };
            glob = { "*" = "allow"; };
            grep = { "*" = "allow"; };
          };
        };
      };
    };
  };
}
