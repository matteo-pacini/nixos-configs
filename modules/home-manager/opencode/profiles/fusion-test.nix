# fusion-test profile — experimental. plan + review run the OpenRouter Fusion
# router with the "trifecta" preset: a 3-model panel (kimi-k2.7-code,
# deepseek-v4-pro, glm-5.1) reconciled by a gemini-2.5-flash judge.
# build/explore/debug fall back to the default model. The preset is delivered by
# the openrouter-fusion-presets patch via OPENCODE_FUSION_PRESETS (opencode 1.16.2
# has no native custom-panel config). Prices come from ../model-prices.nix; cost
# visibility relies on the openrouter-real-cost patch (overlays/shared.nix).
{
  defaultModel = "openrouter/google/gemini-2.5-flash";
  smallModel = "openrouter/google/gemini-2.5-flash-lite";

  steering = [
    ''
      ## Fusion panel

      On `plan` and `review`, OpenRouter Fusion convenes a multi-model panel
      (kimi-k2.7-code, deepseek-v4-pro, glm-5.1) judged by gemini-2.5-flash and
      returns a structured consensus. Treat its analysis as advisory input —
      reconcile any contradictions yourself before answering.
    ''
  ];

  # build runs the Kimi coding specialist — gemini-flash is too weak to
  # implement. K2.* sampling (temperature 1.0 + explicit top_p 0.95) per kimi.nix.
  roles.build = {
    model = "openrouter/moonshotai/kimi-k2.7-code";
    temperature = 1.0;
    topP = 0.95;
  };

  # preset → the variant name agents select; panel/judge are bare OpenRouter ids
  # (Fusion API fields, resolved server-side, not opencode slugs).
  fusion = {
    preset = "trifecta";
    agents = [
      "plan"
      "review"
    ];
    judge = "google/gemini-2.5-flash";
    panel = [
      "moonshotai/kimi-k2.7-code"
      "deepseek/deepseek-v4-pro"
      "z-ai/glm-5.1"
    ];
  };

  # TUI label for the Fusion router (surfaces when the panel convenes); plain
  # gemini-2.5-flash turns keep their real name. P = panel, J = judge.
  modelNames."openrouter/fusion" = "P K2.7 DSv4 GLM5.1 J G2.5F";
}
