# OpenCode configuration — research-backed agent tuning.
# ============================================================================
#
# Verification (run after `darwin-rebuild switch` on a host with this enabled):
#
#   OPENCODE_LOG_LEVEL=DEBUG opencode run --agent build "say hi" 2>&1 \
#     | grep -iE 'temperature|top_p|reasoning'
#
#   Expect `reasoning: { effort: "..." }` in the outgoing request body.
#   A bare top-level `reasoningEffort: "..."` is silently DROPPED by OpenRouter
#   (only the nested `reasoning.effort` shape is recognised).
#
# Inspecting merged config:
#   opencode debug agent build       # resolved per-agent settings
#   opencode debug config            # merged top-level config
#
# ----------------------------------------------------------------------------
# Primary references:
#   Schema:           https://opencode.ai/config.json
#   Agent docs:       https://opencode.ai/docs/agents/
#   Config docs:      https://opencode.ai/docs/config/
#   Permission docs:  https://opencode.ai/docs/permissions/
#   OpenCode source:  https://github.com/sst/opencode
#                     (packages/opencode/src/provider/transform.ts holds the
#                      model-specific default temperature/top_p, plus the
#                      reasoning-passthrough whitelist that excludes Kimi /
#                      DeepSeek-V4 / MiniMax / GLM / Qwen)
#   OpenRouter:       https://openrouter.ai/docs/guides/best-practices/reasoning-tokens
#
# ----------------------------------------------------------------------------
# Open issues to monitor (snapshot 2026-04-28):
#   anomalyco/opencode#24569 + #24722  DeepSeek V4 reasoning_content not
#                                       round-tripped → 400 on multi-turn
#                                       tool calls. If `explore` fires this,
#                                       drop its options.reasoning.effort.
#   anomalyco/opencode#23334 / PR #23335  Proposes lifting the Kimi/Qwen
#                                          exclusion from variants() so that
#                                          the reasoning passthrough actually
#                                          reaches Kimi via OpenRouter.
#   anomalyco/opencode#21632  Subagent variants parsed but not applied at
#                              runtime in v1.4.0+.
#   anomalyco/opencode#18634  reasoningEffort=xhigh not visible in TUI/export.
#
# ----------------------------------------------------------------------------
# Conventions used below:
#
#   * `temperature` and `top_p` for Kimi K2.6 follow Moonshot's thinking-mode
#     profile (1.0 / 0.95). Moonshot LOCKS the temperature to the active mode
#     on its official API (thinking=1.0, instant=0.6); OpenRouter relays
#     without erroring but the recommendation still stands. OpenCode also
#     auto-injects 1.0/0.95 for any kimi-k2.5/2.6/k2-thinking model in
#     transform.ts, so the explicit values are documentation-equal-to-default.
#     https://huggingface.co/moonshotai/Kimi-K2.6
#     https://platform.kimi.ai/docs/guide/use-kimi-k2-thinking-model
#
#   * `options.reasoning.effort` (NOT bare `reasoningEffort`). OpenCode
#     normalises agent-level `reasoningEffort` into
#     providerOptions.openrouter.reasoningEffort, which OpenRouter silently
#     ignores. The nested `options.reasoning.effort` form lands at
#     providerOptions.openrouter.reasoning.effort — the shape OpenRouter
#     actually consumes (verified in OpenRouterTeam/ai-sdk-provider source
#     and tests).
#
#   * `steps` defaults to Infinity if unset (`agent.steps ?? Infinity` in
#     packages/opencode/src/session/prompt.ts). Always cap explicitly.
#     Community range observed across 12+ public configs: 4 to 400; this
#     config sits on the conservative side of normal.
#
#   * `permission.write` is NOT a canonical permission key per the schema;
#     it's silently absorbed by additionalProperties and does NOTHING. The
#     `edit` permission already gates the {edit, write, patch} tool group
#     per OpenCode docs.
# ============================================================================

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

    # tui.json — theme, keybinds, TUI settings.
    # The root opencode.json schema has additionalProperties:false and rejects
    # `theme` at top level. Modern strict validators flag it; runtime currently
    # accepts via fallback but the canonical placement is a sibling tui.json.
    home.file.".config/opencode/tui.json".text = builtins.toJSON {
      theme = "dracula";
    };

    home.file.".config/opencode/opencode.json".text = builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";

      # Nix manages the package version. The nixpkgs derivation does NOT
      # suppress this on its own — only OPENCODE_DISABLE_MODELS_FETCH is set
      # there. Without this opt-out, OpenCode tries to self-update its binary
      # in /nix/store (read-only) and emits "update available" notices.
      autoupdate = false;

      # Default model for any agent that doesn't override.
      # Kimi K2.6 chosen for long-horizon agentic work — Moonshot's design
      # target is 200-300 sequential tool calls and a 4000-step horizon, with
      # benchmark numbers achieved at temp=1.0, top_p=1.0 (build mirrors model
      # card 0.95 instead of benchmark 1.0; both are valid, 0.95 matches
      # OpenCode's auto-default).
      # https://openrouter.ai/moonshotai/kimi-k2.6  (~$0.74 in / $4.65 out per Mtok, 256k ctx)
      model = "openrouter/moonshotai/kimi-k2.6";

      # small_model — title generation, conversation summarisation, lightweight
      # auxiliary calls. OpenCode schema makes this a STRING ONLY: no per-call
      # parameter overrides are possible (verified against
      # https://opencode.ai/config.json — the field is `{type: "string",
      # $ref: "model-schema.json#/$defs/Model"}`).
      #
      # Gemini 2.5 Flash Lite chosen because:
      #   1. Same provider family as the review agent's Gemini 3 Flash.
      #   2. No reasoning overhead — using gemini-3-flash-preview here would
      #      route every 5-token title through thinking_level=high (Gemini 3's
      #      hardcoded default in OpenCode's transform.ts:875-877), wasteful at
      #      $3.00 per Mtok output.
      #   3. GA, not preview. ~$0.10 in / $0.40 out per Mtok.
      # https://openrouter.ai/google/gemini-2.5-flash-lite
      small_model = "openrouter/google/gemini-2.5-flash-lite";

      # AGENTS.md auto-discovery walks up from cwd anyway; listing it
      # explicitly documents the dependency for any custom rules in the file.
      instructions = [ "AGENTS.md" ];

      agent = {

        # ----------------------------------------------------------------
        # build — primary implementation agent (full coding/edit/bash).
        #   Sampling: Kimi K2.6 thinking-mode profile (Moonshot model card).
        #   steps=50 matches Moonshot's published max-steps multi-step eval
        #   ceiling. Community precedent: arvinmi=50, pshevche=80, ushiradineth
        #   builder=80 (Kimi-class build agents typically sit 50-100).
        # ----------------------------------------------------------------
        build = {
          description = "Full-featured coding agent for implementation and complex changes. Writes code, runs tests, manages files, and executes system commands. Use for: building features, bug fixes, large refactors, dependency updates, and any task requiring code modifications.";
          mode = "primary";
          model = "openrouter/moonshotai/kimi-k2.6";
          temperature = 1.0;
          top_p = 0.95;
          # KIMI CAVEAT: OpenCode has no client-side thinking-on toggle for
          # Kimi via OpenRouter — auto-thinking is gated to @ai-sdk/anthropic
          # only (transform.ts ~lines 914-922). This value propagates as
          # `reasoning: { effort: "high" }` in the request body; whether
          # thinking actually engages depends on the OpenRouter→Moonshot
          # gateway honouring it. See issue #23334 for proposal to lift the
          # Kimi exclusion in variants().
          options = {
            reasoning = { effort = "high"; };
          };
          steps = 50;
        };

        # ----------------------------------------------------------------
        # plan — primary, read-only architecture/design.
        #   Most reasoning-bound role in the config — gets `xhigh` (≈95% of
        #   max_tokens budget allocated to reasoning per OpenRouter spec).
        #   Kimi's underlying API is binary thinking on/off, so xhigh likely
        #   maps to "high" upstream — that's still the right intent.
        # ----------------------------------------------------------------
        plan = {
          description = "Architecture and planning specialist. Analyzes code, designs solutions, and creates implementation plans without modifying files. Use for: system design, code review preparation, technical decisions, refactoring strategies, and understanding complex codebases.";
          mode = "primary";
          model = "openrouter/moonshotai/kimi-k2.6";
          temperature = 1.0;
          top_p = 0.95;
          options = {
            reasoning = { effort = "xhigh"; };
          };
          steps = 20;
          permission = {
            edit = { "*" = "deny"; };
            bash = { "*" = "deny"; };
          };
        };

        # ----------------------------------------------------------------
        # explore — subagent, read-only codebase navigator.
        #   DeepSeek V4 Flash chosen for cheap fast retrieval ($0.14/$0.28
        #   per Mtok). Model card mandates temp=1.0, top_p=1.0 across ALL
        #   modes — explicitly supersedes the legacy V3 per-task table that
        #   said coding=0.0. Lower values (the GPT/Claude habit) are
        #   documented anti-patterns for V4.
        #   https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash
        # ----------------------------------------------------------------
        explore = {
          description = "Fast codebase navigator for discovery and analysis. Searches files, finds references, maps dependencies, and answers questions about code structure. Use for: understanding unfamiliar codebases, finding functions/classes, tracing data flows, and locating configuration.";
          mode = "subagent";
          model = "openrouter/deepseek/deepseek-v4-flash";
          temperature = 1.0;
          top_p = 1.0;
          # NOT xhigh — that maps to DeepSeek "Think Max" which requires
          # ≥384K context (393,216 per the vLLM recipe) and burns ~95% of the
          # token budget on reasoning. Wrong for a blocking subagent that a
          # primary is waiting on.
          #
          # WATCH-OUT: anomalyco/opencode#24569 + #24722 (open) report 400s
          # on V4 multi-turn tool calls when reasoning is enabled, because
          # reasoning_content is not round-tripped via OpenRouter. If this
          # fires on real usage, drop the options block and accept Non-think
          # mode for explore.
          options = {
            reasoning = { effort = "high"; };
          };
          steps = 20;
          permission = {
            edit = { "*" = "deny"; };
            bash = { "*" = "deny"; };
            read = { "*" = "allow"; };
            glob = { "*" = "allow"; };
            grep = { "*" = "allow"; };
          };
        };

        # ----------------------------------------------------------------
        # review — subagent, code quality + security review.
        #   No temperature/top_p — Google explicitly warns that any override
        #   below default 1.0 causes "looping or degraded performance,
        #   particularly with complex reasoning tasks." Defaults: 1.0/0.95.
        #   https://ai.google.dev/gemini-api/docs/gemini-3
        #
        #   No options.reasoning.effort either — OpenCode's transform.ts
        #   (~lines 875-877) unconditionally hardcodes
        #   `reasoning: { effort: "high" }` for any gemini-3* model.
        #   Setting it here would be silently redundant.
        # ----------------------------------------------------------------
        review = {
          description = "Code quality and security reviewer. Identifies bugs, security vulnerabilities, performance issues, and style violations. Use for: PR reviews, security audits, best practice enforcement, and spotting potential edge cases or anti-patterns.";
          mode = "subagent";
          model = "openrouter/google/gemini-3-flash-preview";
          steps = 20;
          permission = {
            edit = { "*" = "deny"; };
            bash = { "*" = "deny"; };
            read = { "*" = "allow"; };
            glob = { "*" = "allow"; };
            grep = { "*" = "allow"; };
          };
        };

        # ----------------------------------------------------------------
        # debug — subagent, troubleshooting with bash.
        #   steps=30 sized for diagnostic loops (test → observe →
        #   re-hypothesise → test). Community qa/diagnostic agents on
        #   Kimi-class typically 50-80; 30 is conservative within that band
        #   while still well above plan/build's read-only ceiling.
        # ----------------------------------------------------------------
        debug = {
          description = "Diagnostic specialist for troubleshooting and investigation. Runs tests, inspects logs, reproduces issues, and analyzes error patterns. Use for: debugging failures, investigating performance issues, analyzing test results, and diagnosing system problems.";
          mode = "subagent";
          model = "openrouter/moonshotai/kimi-k2.6";
          temperature = 1.0;
          top_p = 0.95;
          options = {
            reasoning = { effort = "high"; };
          };
          steps = 30;
          permission = {
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
