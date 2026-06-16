{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = config.custom.opencode;

  # Built-in profiles: data lives in the module, hosts just toggle .enable.
  builtinProfiles = {
    kimi = import ./opencode/profiles/kimi.nix;
    glm = import ./opencode/profiles/glm.nix;
  };

  catalog = import ./opencode/model-prices.nix;
  mkDoc = (import ./agents-md.nix { inherit lib; }).mkDoc;

  # Per-role invariants (description/mode/steps/permission) shared once; profiles add only model + sampling.
  agentSkeleton = {
    build = {
      description = "Full-featured coding agent for implementation and complex changes. Writes code, runs tests, manages files, and executes system commands. Use for: building features, bug fixes, large refactors, dependency updates, and any task requiring code modifications.";
      mode = "primary";
      steps = 50;
    };
    plan = {
      description = "Architecture and planning specialist. Analyzes code, designs solutions, and creates implementation plans without modifying files. Use for: system design, code review preparation, technical decisions, refactoring strategies, and understanding complex codebases.";
      mode = "primary";
      steps = 20;
      permission = {
        edit = { "*" = "deny"; };
        bash = { "*" = "deny"; };
      };
    };
    explore = {
      description = "Fast codebase navigator for discovery and analysis. Searches files, finds references, maps dependencies, and answers questions about code structure. Use for: understanding unfamiliar codebases, finding functions/classes, tracing data flows, and locating configuration.";
      mode = "subagent";
      steps = 40;
      permission = {
        edit = { "*" = "deny"; };
        bash = { "*" = "deny"; };
        read = { "*" = "allow"; };
        glob = { "*" = "allow"; };
        grep = { "*" = "allow"; };
      };
    };
    review = {
      description = "Code quality and security reviewer. Identifies bugs, security vulnerabilities, performance issues, and style violations. Use for: PR reviews, security audits, best practice enforcement, and spotting potential edge cases or anti-patterns.";
      mode = "subagent";
      steps = 20;
      permission = {
        edit = { "*" = "deny"; };
        bash = { "*" = "deny"; };
        read = { "*" = "allow"; };
        glob = { "*" = "allow"; };
        grep = { "*" = "allow"; };
      };
    };
    debug = {
      description = "Diagnostic specialist for troubleshooting and investigation. Runs tests, inspects logs, reproduces issues, and analyzes error patterns. Use for: debugging failures, investigating performance issues, analyzing test results, and diagnosing system problems.";
      mode = "subagent";
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

  # Merge skeleton invariants with the profile's model + optional sampling
  # (variant/temp/top_p only when set). opencode's JSON key is snake_case top_p;
  # profiles write camelCase topP.
  mkAgent =
    roleName: role:
    agentSkeleton.${roleName}
    // { model = role.model; }
    // lib.optionalAttrs ((role.variant or null) != null) { variant = role.variant; }
    // lib.optionalAttrs ((role.temperature or null) != null) { temperature = role.temperature; }
    // lib.optionalAttrs ((role.topP or null) != null) { top_p = role.topP; };

  # Every model a profile touches (roles + default + small), as bare ids — used
  # to pull pricing from the shared catalog.
  profileModels =
    profile:
    let
      strip = lib.removePrefix "openrouter/";
    in
    lib.unique (
      [
        (strip profile.defaultModel)
        (strip profile.smallModel)
      ]
      ++ map (r: strip r.model) (lib.attrValues (profile.roles or { }))
    );

  # A profile is a data attrset:
  #   { defaultModel; smallModel; roles ? { }; steering ? [ ]; }
  # where roles.<name> = { model; variant ? null; temperature ? null; topP ? null; }.
  mkProfile =
    alias: profile:
    let
      roles = profile.roles or { };

      # Privacy: route every OpenRouter request only to Zero-Data-Retention,
      # no-training providers. opencode forwards a model's options.provider verbatim
      # to the OpenRouter request body.
      routing.provider = {
        zdr = true;
        data_collection = "deny";
      };
      providerModels = lib.mapAttrs (
        _slug: entry: entry // { options = routing; }
      ) (lib.genAttrs (profileModels profile) (slug: catalog.${slug}));

      opencodeConfig = pkgs.writeText "opencode-${alias}.json" (
        builtins.toJSON {
          "$schema" = "https://opencode.ai/config.json";
          autoupdate = false;
          model = profile.defaultModel;
          small_model = profile.smallModel;
          provider.openrouter.models = providerModels;
          agent = lib.mapAttrs mkAgent roles;
        }
      );

      agentsMd = pkgs.writeText "opencode-${alias}-AGENTS.md" (mkDoc {
        needsRtkPrompt = true;
        afterSimplicity = profile.steering or [ ];
      });

      confDir = pkgs.runCommand "opencode-${alias}-confdir" { } (
        ''
          mkdir -p "$out/plugin"
          install -m444 ${opencodeConfig} "$out/opencode.json"
          install -m444 ${agentsMd} "$out/AGENTS.md"
          install -m444 ${./opencode/rtk.ts} "$out/plugin/rtk.ts"
        ''
        # opencode writes a .gitignore into the config dir at startup; on a
        # read-only store path that write crashes config load, so pre-ship it.
        + ''
          printf '%s\n' node_modules package.json package-lock.json bun.lock .gitignore > "$out/.gitignore"
        ''
      );
    in
    pkgs.writeShellApplication {
      name = "opencode-${alias}";
      runtimeInputs = [
        pkgs.opencode
        pkgs.rtk
        pkgs.coreutils
      ];
      text =
        ''
          export OPENCODE_CONFIG_DIR=${confDir}
          root="$HOME/.local/share/opencode-${alias}"
          export XDG_DATA_HOME="$root/data"
          export XDG_STATE_HOME="$root/state"
          export XDG_CACHE_HOME="$root/cache"
          mkdir -p "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
        ''
        + lib.optionalString (cfg.openrouterKeyFile != null) ''
          if [ -r "${cfg.openrouterKeyFile}" ]; then
            set -a
            # shellcheck disable=SC1090,SC1091
            . "${cfg.openrouterKeyFile}"
            set +a
          else
            echo "opencode-${alias}: ${cfg.openrouterKeyFile} unreadable; run 'opencode auth login' or deploy the agenix secret" >&2
          fi
        ''
        + ''
          exec opencode "$@"
        '';
    };

  enabledProfiles = lib.filterAttrs (name: _: cfg.profiles.${name}.enable or false) builtinProfiles;
in
{
  options.custom.opencode = {
    enable = lib.mkEnableOption "OpenCode profile launchers (opencode-<alias>)";

    openrouterKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = lib.attrByPath [
        "age"
        "secrets"
        "openrouter.env"
        "path"
      ] null osConfig;
      defaultText = lib.literalExpression ''osConfig.age.secrets."openrouter.env".path or null'';
      description = "Env file defining OPENROUTER_API_KEY, sourced by every launcher. Defaults to the agenix path of the shared openrouter.env secret.";
    };

    profiles = lib.mkOption {
      default = { };
      description = "Built-in OpenCode profiles to enable; each becomes the opencode-<name> launcher.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.enable = lib.mkEnableOption "this OpenCode profile";
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (n: builtinProfiles ? ${n}) (lib.attrNames cfg.profiles);
        message = "custom.opencode.profiles: unknown profile(s) ${lib.concatStringsSep ", " (lib.subtractLists (lib.attrNames builtinProfiles) (lib.attrNames cfg.profiles))}; known: ${lib.concatStringsSep ", " (lib.attrNames builtinProfiles)}";
      }
    ];
    home.packages = lib.mapAttrsToList mkProfile enabledProfiles;
  };
}
