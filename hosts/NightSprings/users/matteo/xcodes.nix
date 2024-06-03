{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:
{
  programs.xcodes = {
    enable = true;
    enableAria = true;
    versions = [ "15.4" ];
    active = "15.4";
  };
}
