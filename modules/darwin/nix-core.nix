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
    enable = lib.mkEnableOption "Shared Nix and Nixpkgs configuration for Darwin hosts";
    trustedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "root" ];
      description = "List of trusted Nix users";
    };
  };

  config = lib.mkIf cfg.enable {
    nix = {
      nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
      registry = {
        nixpkgs.flake = inputs.nixpkgs;
      };
      extraOptions = ''
        extra-platforms = x86_64-darwin aarch64-darwin
      '';
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = cfg.trustedUsers;
        sandbox = "relaxed";
      };
    };
    nixpkgs.config.allowUnfree = true;
  };
}
