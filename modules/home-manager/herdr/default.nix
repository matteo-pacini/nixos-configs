{ lib, ... }:
{
  imports = [
    ./core.nix
    ./agent-labels.nix
    ./workbench.nix
  ];

  options.custom.herdr = {
    enable = lib.mkEnableOption "herdr-core (`hc`), the server that runs Herdr's terminals and agents";
    desktop = lib.mkEnableOption "the Herdr desktop app";
  };
}
