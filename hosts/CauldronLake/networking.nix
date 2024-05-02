{
  config,
  pkgs,
  lib,
  ...
}: {
  networking.hostName = "CauldronLake";

  networking.firewall.enable = false;

  networking.networkmanager.enable = true;
}
