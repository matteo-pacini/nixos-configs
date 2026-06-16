# Per-model price/limit catalog, the single pricing source for all profiles.
# Numbers mirror models.dev (opencode's catalog); OpenRouter does the billing.
# Keys are bare OpenRouter ids; a profile's provider.openrouter.models is derived
# from the models it references, so prices live here once.
{
  "moonshotai/kimi-k2.7-code" = {
    name = "Kimi K2.7 Code";
    limit = {
      context = 262144;
      output = 262144;
    };
    cost = {
      input = 0.75;
      output = 3.5;
      cache_read = 0.16;
    };
  };
  "moonshotai/kimi-k2.6" = {
    name = "Kimi K2.6";
    limit = {
      context = 262142;
      output = 262142;
    };
    cost = {
      input = 0.68;
      output = 3.41;
      cache_read = 0.34;
    };
  };
  "moonshotai/kimi-k2.5" = {
    name = "Kimi K2.5";
    limit = {
      context = 256000;
      output = 262144;
    };
    cost = {
      input = 0.375;
      output = 2.025;
    };
  };
  # z-ai GLM family
  "z-ai/glm-5.2" = {
    name = "GLM 5.2";
    limit = {
      context = 1048576;
      output = 131072;
    };
    cost = {
      input = 1.4;
      output = 4.4;
      cache_read = 0.26;
    };
  };
  "z-ai/glm-5.1" = {
    name = "GLM 5.1";
    limit = {
      context = 202752;
      output = 131072;
    };
    cost = {
      input = 0.98;
      output = 3.08;
      cache_read = 0.182;
    };
  };
  "z-ai/glm-5" = {
    name = "GLM 5";
    limit = {
      context = 202752;
      output = 131072;
    };
    cost = {
      input = 0.60;
      output = 1.92;
      cache_read = 0.12;
    };
  };
  "z-ai/glm-4.7-flash" = {
    name = "GLM 4.7 Flash";
    limit = {
      context = 202752;
      output = 16384;
    };
    cost = {
      input = 0.06;
      output = 0.40;
      cache_read = 0.01;
    };
  };
  "google/gemini-2.5-flash" = {
    name = "Gemini 2.5 Flash";
    limit = {
      context = 1048576;
      output = 65535;
    };
    cost = {
      input = 0.3;
      output = 2.5;
      reasoning = 2.5;
      cache_read = 0.03;
      cache_write = 0.083333;
    };
  };
  "google/gemini-2.5-flash-lite" = {
    name = "Gemini 2.5 Flash-Lite";
    limit = {
      context = 1048576;
      output = 65535;
    };
    cost = {
      input = 0.1;
      output = 0.4;
      reasoning = 0.4;
      cache_read = 0.01;
      cache_write = 0.083333;
    };
  };
}
