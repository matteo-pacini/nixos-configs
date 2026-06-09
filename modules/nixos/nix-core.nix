{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.custom.nix-core;

  # One-shot push of the running system to the cache, using the agenix
  # token; leaves no attic client config behind
  atticPushCurrentSystem = pkgs.writeShellApplication {
    name = "attic-push-current-system";
    runtimeInputs = [
      pkgs.attic-client
      pkgs.gawk
    ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "must run as root: the attic token is root-readable only" >&2
        exit 1
      fi
      token=$(awk '/^password/ { print $2 }' "${toString cfg.atticCache.netrcFile}")
      XDG_CONFIG_HOME=$(mktemp -d)
      export XDG_CONFIG_HOME
      trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT
      attic login nexus https://cache.matteopacini.me "$token"
      attic push main /run/current-system
    '';
  };
in
{
  options.custom.nix-core = {
    enable = lib.mkEnableOption "Shared Nix and Nixpkgs configuration for NixOS hosts";
    trustedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "root" ];
      description = "List of trusted Nix users";
    };
    extraPlatforms = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra platforms for cross-compilation support";
    };
    permittedInsecurePackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of insecure packages to permit";
    };
    atticCache = {
      enable = lib.mkEnableOption "the self-hosted attic cache as a system-level substituter";
      netrcFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "netrc file with the attic token, for pulling from the private cache";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        nix = {
          nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
          registry = {
            nixpkgs.flake = inputs.nixpkgs;
          };
          settings = {
            experimental-features = [
              "nix-command"
              "flakes"
            ];
            trusted-users = cfg.trustedUsers;
          };
        };
        nixpkgs.config.allowUnfree = true;
      }
      (lib.mkIf (cfg.extraPlatforms != [ ]) {
        nix.settings.extra-platforms = cfg.extraPlatforms;
      })
      (lib.mkIf (cfg.permittedInsecurePackages != [ ]) {
        nixpkgs.config.permittedInsecurePackages = cfg.permittedInsecurePackages;
      })
      # System-level so the substituter applies to every user (the
      # nix-daemon performs all downloads), with no flake nixConfig
      # trust prompts
      (lib.mkIf cfg.atticCache.enable {
        nix.settings = {
          extra-substituters = [ "https://cache.matteopacini.me/main" ];
          extra-trusted-public-keys = [ "main:qAfi80bao6jxVrLVIuX07sthJscb2CcFBboYsEBxdG4=" ];
        }
        // lib.optionalAttrs (cfg.atticCache.netrcFile != null) {
          netrc-file = cfg.atticCache.netrcFile;
        };

        environment.systemPackages = lib.optionals (cfg.atticCache.netrcFile != null) [
          atticPushCurrentSystem
        ];
      })
    ]
  );
}
