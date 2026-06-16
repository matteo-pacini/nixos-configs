# GLM profile — all-GLM agentic roster. Prices come from ../model-prices.nix.
# glm-5.1: SWE-bench Pro SOTA (58.4), 8h autonomous execution. Primary coder.
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
    # glm-5.1: SWE-bench Pro SOTA (58.4), 8h autonomous execution, strongest
    # family agentic. Primary 50-step coder — cost $0.98/Mtok justified.
    build = {
      model = "openrouter/z-ai/glm-5.1";
      temperature = 1.0;
      topP = 0.95;
    };
    # glm-5.1: same agentic strength + thinking-on by default; plan is read-only
    # so cost parity with build is fine for architecture sketches.
    plan = {
      model = "openrouter/z-ai/glm-5.1";
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
