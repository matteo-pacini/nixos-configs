{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.custom.nix-core;
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

        # Client for the self-hosted attic cache on Nexus
        environment.systemPackages = [ pkgs.attic-client ];
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
      })
    ]
  );
}
