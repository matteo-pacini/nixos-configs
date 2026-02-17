{
  config,
  lib,
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
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
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
  ]);
}
