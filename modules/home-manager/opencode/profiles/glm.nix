# GLM profile — all-GLM agentic roster. Prices come from ../model-prices.nix.
# glm-5.2: 1M-token context (vs 5.1's ~200K), vendor-claimed SWE-bench Pro 62.1
#   (no independent verify). Primary coder for build + plan.
# glm-5.1: SWE-bench Pro SOTA (58.4), 8h autonomous execution. Debug fallback.
# glm-5: strong family code index, cheaper, good for read-only review.
# glm-4.7-flash: ultra-cheap ($0.06/Mtok) for navigation and summaries.
# Default sampling: temp=1.0, top_p=0.95 per Z.AI official recommendation.
{
  defaultModel = "openrouter/z-ai/glm-5.1";
  smallModel = "openrouter/z-ai/glm-4.7-flash";

  steering = [
    ''
      ## Output Discipline

      Always respond and reason in English — do not switch to Chinese in
      thinking blocks or output.

      When a decision could go either way between brevity and edge-case safety,
      **choose brevity**. Stop self-critique loops once a workable answer is
      reached — do not re-litigate simplicity-vs-robustness trade-offs. If you
      have considered both sides once, commit and move on; the user can ask for
      the alternative if needed.

      If a tool call errors, change approach before retrying — never repeat the
      identical failing call. When you have enough context to act, act; don't
      re-grep or re-read what's already in context.

      Execute tasks in explicit numbered sub-steps. Do not rely on mid-task
      self-correction — if a step fails, stop and report before proceeding.
    ''
  ];

  # temp 1.0 / top_p 0.95 = Z.AI's recommended sampling, not a hard lock: every
  # tool-capable ZDR GLM endpoint exposes both temperature + top_p, no reject
  # pattern. explore (glm-4.7-flash) omits both and inherits server-side defaults.
  roles = {
    # glm-5.2: 1M-token context + vendor-claimed SWE-bench Pro 62.1 (vs 5.1's
    # 58.4). Primary 50-step coder; ZDR-confirmed, $1.40/Mtok in.
    build = {
      model = "openrouter/z-ai/glm-5.2";
      temperature = 1.0;
      topP = 0.95;
    };
    # glm-5.2: 1M-token context (vs 5.1's 202752) suits whole-codebase
    # architecture sketches; plan is read-only so it can't poison the 50-step
    # build chain. ZDR-confirmed (Z.AI/Io Net/Novita/Friendli, fp8, tools+temp+top_p).
    plan = {
      model = "openrouter/z-ai/glm-5.2";
      temperature = 1.0;
      topP = 0.95;
    };
    # glm-4.7-flash: $0.06/Mtok, sufficient for read-only nav/grep. Inherits
    # server-side temp=1.0/top_p=0.95 (bare assignment, like kimi explore).
    explore.model = "openrouter/z-ai/glm-4.7-flash";
    # glm-5: strong family code index, structured_outputs, $0.60 vs $0.98.
    review = {
      model = "openrouter/z-ai/glm-5";
      temperature = 1.0;
      topP = 0.95;
    };
    # glm-5.1: bash investigation needs strongest long-horizon tool execution.
    debug = {
      model = "openrouter/z-ai/glm-5.1";
      temperature = 1.0;
      topP = 0.95;
    };
  };
}
