# Kimi profile — all-Kimi agentic roster. Prices come from ../model-prices.nix.
{
  defaultModel = "openrouter/moonshotai/kimi-k2.6";
  smallModel = "openrouter/google/gemini-2.5-flash-lite";

  steering = [
    ''
      ## Output Discipline

      When a decision could go either way between brevity and edge-case safety,
      **choose brevity**. Stop self-critique loops once a workable answer is
      reached — do not re-litigate simplicity-vs-robustness trade-offs. If you
      have considered both sides once, commit and move on; the user can ask for
      the alternative if needed.

      If a tool call errors, change approach before retrying — never repeat the
      identical failing call. When you have enough context to act, act; don't
      re-grep or re-read what's already in context.
    ''
  ];

  # temp 1.0 / top_p 0.95 = Moonshot's recommended sampling, not a hard lock:
  # only their first-party/DigitalOcean/Fireworks endpoints reject overrides;
  # the ZDR providers we route to accept them. explore (k2.5) omits both and
  # inherits the same server-side defaults.
  roles = {
    build = {
      model = "openrouter/moonshotai/kimi-k2.7-code";
      temperature = 1.0;
      topP = 0.95;
    };
    plan = {
      model = "openrouter/moonshotai/kimi-k2.6";
      temperature = 1.0;
      topP = 0.95;
    };
    explore.model = "openrouter/moonshotai/kimi-k2.5";
    review = {
      model = "openrouter/moonshotai/kimi-k2.6";
      temperature = 1.0;
      topP = 0.95;
    };
    debug = {
      model = "openrouter/moonshotai/kimi-k2.7-code";
      temperature = 1.0;
      topP = 0.95;
    };
  };
}
