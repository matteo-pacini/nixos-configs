{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = config.custom.opencode;

  privacyRouting = {
    zdr = true;
    data_collection = "deny";
  };

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
    provider.openrouter.options.extraBody.provider = privacyRouting;
    # Skip providers whose cached-input price is several times the norm for
    # this model (cache-heavy agent sessions). Model-level options are spread
    # over the request body after extraBody, so this `provider` object
    # replaces the one above for this model — the privacy flags must be
    # repeated here or they'd be dropped.
    provider.openrouter.models."deepseek/deepseek-v4.1-flash".options.provider = privacyRouting // {
      ignore = [
        "wafer"
        "inference-net"
        "relace"
      ];
      allow_fallbacks = true;
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

    # Drops the legacy herdr TUI's opencode integration: a server plugin, two
    # TUI plugins and the tui.jsonc / cli.json entries that load them. All
    # were written at runtime, so Home Manager never owned them; they need the
    # TUI's socket and do nothing without it. Other entries in those files are
    # kept, and a file left empty is removed.
    home.activation.opencodeHerdrCleanup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      dir="${config.xdg.configHome}/opencode"
      run rm -rf "$dir/plugins/herdr-agent-state.js" "$dir/herdr-tui-session.js" "$dir/herdr-opencode"
      for f in tui.jsonc:plugin:./herdr-tui-session.js cli.json:plugins:./herdr-opencode; do
        file="$dir/''${f%%:*}" rest="''${f#*:}" key="''${rest%%:*}" entry="''${rest#*:}"
        [ -f "$file" ] || continue
        tmp=$(mktemp)
        if ${lib.getExe pkgs.jq} --arg key "$key" --arg entry "$entry" '
          if has($key) then .[$key] |= map(select(. != $entry)) | if .[$key] == [] then del(.[$key]) else . end else . end
        ' "$file" > "$tmp"; then
          if [ "$(${lib.getExe pkgs.jq} -c . "$tmp")" = "{}" ]; then run rm -f "$file"; else run mv "$tmp" "$file"; fi
        fi
        rm -f "$tmp"
      done
    '';
  };
}
