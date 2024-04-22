{
  config,
  pkgs,
  lib,
  ...
}: {
  networking.hostName = "BrightFalls";

  networking.useDHCP = lib.mkDefault true;
  networking.interfaces.enp3s0.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;
}
