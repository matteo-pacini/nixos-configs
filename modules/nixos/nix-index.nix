{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.custom.nix-index;
in
{
  imports = [ inputs.nix-index-database.nixosModules.nix-index ];

  options.custom.nix-index = {
    enable = lib.mkEnableOption "nix-index with prebuilt database (flake-friendly command-not-found replacement)";
    comma = lib.mkEnableOption "comma (`,` run-without-installing) wrapper backed by the prebuilt index";
  };

  # Bind upstream toggle directly: the upstream module's `programs.nix-index-database.enable`
  # defaults to true, so a plain `mkIf cfg.enable` wrapper here would leak it on when off.
  # `programs.command-not-found.enable` is force-disabled because nixpkgs auto-enables it via
  # `pathExists dbPath`, and on flake systems that path doesn't exist at eval time, causing
  # both an assertion conflict with nix-index's shell integration and a path-coercion error.
  config = {
    programs.nix-index-database.enable = cfg.enable;
    programs.nix-index-database.comma.enable = cfg.enable && cfg.comma;
    programs.command-not-found.enable = lib.mkIf cfg.enable (lib.mkForce false);
  };
}
