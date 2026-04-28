{
  config,
  lib,
  pkgs,
  inputs,
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
    home.packages = [ pkgs.opencode ];
    home.file.".config/opencode/themes/dracula.json".source = "${inputs.opencode-dracula-theme}/dracula.json";
    home.file.".config/opencode/opencode.json".text = builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      theme = "dracula";
      autoupdate = false;
      model = "openrouter/moonshotai/kimi-k2.6";
      small_model = "openrouter/google/gemini-3-flash-preview";
      instructions = [ "AGENTS.md" ];
      agent = {
        build = {
          description = "Full-featured coding agent for implementation and complex changes. Writes code, runs tests, manages files, and executes system commands. Use for: building features, bug fixes, large refactors, dependency updates, and any task requiring code modifications.";
          mode = "primary";
          model = "openrouter/moonshotai/kimi-k2.6";
          temperature = 0.2;
          steps = 25;
        };
        plan = {
          description = "Architecture and planning specialist. Analyzes code, designs solutions, and creates implementation plans without modifying files. Use for: system design, code review preparation, technical decisions, refactoring strategies, and understanding complex codebases.";
          mode = "primary";
          model = "openrouter/moonshotai/kimi-k2.6";
          temperature = 0.1;
          steps = 15;
          permission = {
            write = { "*" = "deny"; };
            edit = { "*" = "deny"; };
            bash = { "*" = "deny"; };
          };
        };
        explore = {
          description = "Fast codebase navigator for discovery and analysis. Searches files, finds references, maps dependencies, and answers questions about code structure. Use for: understanding unfamiliar codebases, finding functions/classes, tracing data flows, and locating configuration.";
          mode = "subagent";
          model = "openrouter/deepseek/deepseek-v4-flash";
          temperature = 0.1;
          steps = 10;
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
          description = "Code quality and security reviewer. Identifies bugs, security vulnerabilities, performance issues, and style violations. Use for: PR reviews, security audits, best practice enforcement, and spotting potential edge cases or anti-patterns.";
          mode = "subagent";
          model = "openrouter/google/gemini-3-flash-preview";
          temperature = 0.1;
          steps = 10;
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
          description = "Diagnostic specialist for troubleshooting and investigation. Runs tests, inspects logs, reproduces issues, and analyzes error patterns. Use for: debugging failures, investigating performance issues, analyzing test results, and diagnosing system problems.";
          mode = "subagent";
          model = "openrouter/moonshotai/kimi-k2.6";
          temperature = 0.1;
          steps = 15;
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
