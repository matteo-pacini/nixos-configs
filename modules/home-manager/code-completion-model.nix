{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.code-completion-model;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

  # Metal is already the package default on Darwin, so "metal" needs no
  # override — the option value only pins down which backend a host expects
  # and lets the assertions below catch a mismatch.
  # nixpkgs builds CUDA kernels for Turing and newer only, so a card older
  # than that gets a binary with nothing it can run.
  cudaPackages =
    if cfg.cudaCapabilities == null then
      pkgs.cudaPackages
    else
      pkgs.cudaPackages.overrideScope (
        _: prev: {
          flags = prev.flags // {
            cudaCapabilities = cfg.cudaCapabilities;
            cmakeCudaArchitecturesString = lib.concatStringsSep ";" (
              map (c: lib.replaceStrings [ "." ] [ "" ] c) cfg.cudaCapabilities
            );
          };
        }
      );

  package =
    if cfg.acceleration == "cuda" then
      pkgs.llama-cpp.override {
        cudaSupport = true;
        inherit cudaPackages;
      }
    else if cfg.acceleration == "vulkan" then
      pkgs.llama-cpp.override { vulkanSupport = true; }
    else
      pkgs.llama-cpp;

  cacheDir = "${config.xdg.cacheHome}/llama.cpp";

  flags = [
    "--hf-repo"
    "${cfg.model.repo}:${cfg.model.quant}"
    "--host"
    cfg.host
    "--port"
    (toString cfg.port)
    "--ctx-size"
    (toString cfg.contextSize)
    # Lifted from llama.cpp's own --fim-qwen-* presets (common/arg.cpp):
    # oversized batches because FIM reprocesses prefix and suffix on every
    # keystroke, and a cache-reuse floor so KV shifting salvages the
    # unchanged prefix instead of recomputing it.
    "--batch-size"
    "1024"
    "--ubatch-size"
    "1024"
    "--cache-reuse"
    "256"
  ]
  # Quantised V additionally requires flash attention, which the default
  # -fa auto turns on by itself (src/llama-context.cpp).
  ++ lib.optionals (cfg.kvCacheType != null) [
    "--cache-type-k"
    cfg.kvCacheType
    "--cache-type-v"
    cfg.kvCacheType
  ]
  ++ lib.optionals (cfg.device != null) [
    "--device"
    cfg.device
  ]
  # Sleeping tears the model down (destroy()) and reloads it from scratch on
  # the next request, so the first completion after a wake pays both the
  # reload and a full prompt reprocess. Worth it only where the memory is
  # contended.
  ++ lib.optionals (cfg.sleepIdleSeconds != null) [
    "--sleep-idle-seconds"
    (toString cfg.sleepIdleSeconds)
  ]
  ++ cfg.extraFlags;

  command = [ (lib.getExe' package "llama-server") ] ++ flags;
in
{
  options.custom.code-completion-model = {
    enable = lib.mkEnableOption "local llama.cpp FIM server for editor code completion";

    acceleration = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "cuda"
          "vulkan"
          "metal"
        ]
      );
      default = if isDarwin then "metal" else null;
      description = ''
        GPU backend to build llama.cpp against. `null` means the package
        default: CPU on Linux, Metal on Darwin.
      '';
    };

    cudaCapabilities = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      example = [ "6.1" ];
      description = ''
        CUDA compute capabilities to build kernels for, overriding the nixpkgs
        default of 7.5 and up. Cards older than Turing must name their
        capability here or they get a binary with no kernels they can run.
      '';
    };

    model = {
      repo = lib.mkOption {
        type = lib.types.str;
        example = "bartowski/Qwen2.5-Coder-14B-GGUF";
        description = ''
          Hugging Face GGUF repository, downloaded on first start. Must be a
          base model, not an Instruct one — FIM needs the fill-in-middle
          tokens the instruct tunes drop.
        '';
      };

      quant = lib.mkOption {
        type = lib.types.str;
        default = "Q4_K_M";
        description = ''
          Quantisation to pick out of the repo. Matched case-insensitively;
          llama.cpp falls back to the first file in the repo on no match.
          Below roughly 3B parameters prefer Q8_0 — Q4 costs more accuracy
          than it saves memory at that size.
        '';
      };
    };

    contextSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 32768;
      description = "Prompt context in tokens. Sized against VRAM together with `kvCacheType`.";
    };

    kvCacheType = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "f32"
          "f16"
          "bf16"
          "q8_0"
          "q4_0"
          "q4_1"
          "iq4_nl"
          "q5_0"
          "q5_1"
        ]
      );
      default = "q8_0";
      description = ''
        KV cache data type for both K and V. `null` leaves llama.cpp's f16
        default. `q8_0` halves the cache at negligible cost; `q4_0` degrades
        the token-level precision FIM depends on and is best avoided for code.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Listen address. Loopback keeps buffer contents on the machine.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8012;
      description = "Listen port. 8012 is what llama.vim expects by default.";
    };

    device = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "Vulkan0";
      description = ''
        Device to offload to, for hosts exposing more than one GPU to the
        backend. Run `llama-server --list-devices` to get the names.
      '';
    };

    sleepIdleSeconds = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 300;
      description = ''
        Unload the model after this many idle seconds, freeing its memory
        until the next request. `null` keeps it resident for the lifetime of
        the process, which is llama.cpp's own default.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start the server on login. Off by default: the weights are a large,
        mostly idle memory reservation, so bringing it up by hand for a
        session that needs it beats holding it permanently. The unit is
        installed either way and can be started on demand — see
        `docs/code-completion-handbook.md`.
      '';
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra `llama-server` arguments, appended last.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.acceleration == "metal" -> isDarwin;
        message = "custom.code-completion-model: metal acceleration requires a Darwin host.";
      }
      {
        assertion =
          (builtins.elem cfg.acceleration [
            "cuda"
            "vulkan"
          ])
          -> !isDarwin;
        message = "custom.code-completion-model: ${toString cfg.acceleration} acceleration requires a Linux host.";
      }
    ];

    home.packages = [ package ];

    # Weights land here on first start and are reused across restarts. Not in
    # the Nix store: they are multi-gigabyte downloads with no fixed hash.
    systemd.user.services.code-completion-model = lib.mkIf (!isDarwin) {
      Unit = {
        Description = "llama.cpp FIM server for code completion";
        After = [ "network-online.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = lib.escapeShellArgs command;
        Environment = [ "LLAMA_CACHE=${cacheDir}" ];
        Restart = "on-failure";
        RestartSec = 10;
      };
      Install.WantedBy = lib.optionals cfg.autoStart [ "default.target" ];
    };

    launchd.agents.code-completion-model = lib.mkIf isDarwin {
      enable = true;
      config = {
        ProgramArguments = command;
        EnvironmentVariables.LLAMA_CACHE = cacheDir;
        ProcessType = "Background";
        RunAtLoad = cfg.autoStart;
      }
      # Restart on a crash, but leave a deliberate `launchctl kill` dead.
      // lib.optionalAttrs cfg.autoStart { KeepAlive.SuccessfulExit = false; };
    };
  };
}
