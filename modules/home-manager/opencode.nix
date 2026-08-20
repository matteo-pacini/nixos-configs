{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = config.custom.opencode;

  opencodeConfig = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    autoupdate = false;
    # Cheap utility model for title generation and other lightweight tasks;
    # main model is picked at runtime via /model (full models.dev catalog).
    small_model = "openrouter/z-ai/glm-4.7-flash";
    # Privacy: route every OpenRouter request only to Zero-Data-Retention,
    # no-training providers. Provider-level `options` is spread into the shared
    # OpenRouter SDK client, whose `extraBody` is merged into every request —
    # so this covers all models without enumerating them (model-level
    # `options.provider` would only apply to models listed in this file).
    provider.openrouter.options.extraBody.provider = {
      zdr = true;
      data_collection = "deny";
    };
  };

  # AGENTS.md mirrors the claude-code CLAUDE.md — the doc is tool-neutral.
  agentsMd = builtins.readFile ./claude-code/CLAUDE.md;

  launcher = pkgs.writeShellApplication {
    name = "opencode";
    runtimeInputs = [ pkgs.opencode ];
    text =
      lib.optionalString (cfg.openrouterKeyFile != null) ''
        if [ -r "${cfg.openrouterKeyFile}" ]; then
          set -a
          # shellcheck disable=SC1090,SC1091
          . "${cfg.openrouterKeyFile}"
          set +a
        else
          echo "opencode: ${cfg.openrouterKeyFile} unreadable; run 'opencode auth login' or deploy the agenix secret" >&2
        fi
      ''
      + ''
        exec opencode "$@"
      '';
  };
in
{
  options.custom.opencode = {
    enable = lib.mkEnableOption "opencode with OpenRouter ZDR provider config";

    openrouterKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = lib.attrByPath [
        "age"
        "secrets"
        "openrouter.env"
        "path"
      ] null osConfig;
      defaultText = lib.literalExpression ''osConfig.age.secrets."openrouter.env".path or null'';
      description = "Env file defining OPENROUTER_API_KEY, sourced by the launcher. Defaults to the agenix path of the shared openrouter.env secret.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ launcher ];
    xdg.configFile."opencode/opencode.json".text = opencodeConfig;
    xdg.configFile."opencode/AGENTS.md".text = agentsMd;
  };
}
