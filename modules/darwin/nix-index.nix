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
  imports = [ inputs.nix-index-database.darwinModules.nix-index ];

  options.custom.nix-index = {
    enable = lib.mkEnableOption "nix-index with prebuilt database (command-not-found replacement for nix-darwin)";
    comma = lib.mkEnableOption "comma (`,` run-without-installing) wrapper backed by the prebuilt index";
  };

  # nix-darwin has no `programs.command-not-found` option; the upstream Darwin module
  # turns on `programs.nix-index` via `mkDefault true` unconditionally on import,
  # so bind our toggle directly to that option to allow opting out.
  config = {
    programs.nix-index.enable = cfg.enable;
    programs.nix-index-database.comma.enable = cfg.enable && cfg.comma;
  };
}
