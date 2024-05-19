{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../../../shared/home-manager/firefox.nix
  ];
}
