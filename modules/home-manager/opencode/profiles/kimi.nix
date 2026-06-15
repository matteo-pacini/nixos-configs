# Kimi profile — all-Kimi agentic roster. Prices come from ../model-prices.nix.
{
  defaultModel = "openrouter/moonshotai/kimi-k2.6";
  smallModel = "openrouter/google/gemini-2.5-flash-lite";

  steering = [
    ''
      ## Reasoning Budget

      When a decision could go either way between brevity and edge-case safety,
      **choose brevity**. Stop self-critique loops once a workable answer is
      reached — do not re-litigate simplicity-vs-robustness trade-offs. If you
      have considered both sides once, commit and move on; the user can ask for
      the alternative if needed.
    ''
  ];

  # temperature=1.0 is the only value Moonshot K2.* accepts (else HTTP 400);
  # top_p=0.95 is auto-injected by opencode only for k2.5, so k2.6/k2.7-code set
  # it explicitly while k2.5 (explore) sets neither.
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
