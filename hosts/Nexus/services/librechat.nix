{ config, ... }:
{
  services.librechat = {
    enable = true;
    # Note: openFirewall is left as default (false) due to a nixpkgs module bug
    # where cfg.port is referenced but no such option exists. We open the port
    # manually in networking.nix instead.
    enableLocalDB = true;

    meilisearch = {
      enable = true;
    };

    env = {
      ALLOW_REGISTRATION = false;
      HOST = "0.0.0.0";
      PORT = 3080;
    };

    credentials = {
      CREDS_KEY = config.age.secrets."nexus/librechat-creds-key".path;
      CREDS_IV = config.age.secrets."nexus/librechat-creds-iv".path;
      JWT_SECRET = config.age.secrets."nexus/librechat-jwt-secret".path;
      JWT_REFRESH_SECRET = config.age.secrets."nexus/librechat-jwt-refresh-secret".path;
      OPENROUTER_KEY = config.age.secrets."nexus/librechat-openrouter-key".path;
    };

    settings = {
      version = "1.2.1";
      endpoints = {
        custom = [
          {
            name = "OpenRouter";
            apiKey = "\${OPENROUTER_KEY}";
            baseURL = "https://openrouter.ai/api/v1";
            models = {
              default = [
                "google/gemini-3.1-flash-lite-preview"
                "google/gemini-3.1-pro-preview"
                "anthropic/claude-sonnet-4.6"
              ];
              fetch = true;
            };
            titleConvo = true;
            titleModel = "google/gemini-3.1-flash-lite-preview";
            modelDisplayLabel = "OpenRouter";
          }
        ];
      };
    };
  };

  services.meilisearch = {
    enable = true;
    masterKeyFile = config.age.secrets."nexus/meilisearch-master-key".path;
  };
}
