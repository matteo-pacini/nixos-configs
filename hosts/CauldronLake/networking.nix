{
  config,
  pkgs,
  lib,
  ...
}:
{
  networking.hostName = "CauldronLake";

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
  };

  networking.networkmanager.enable = true;

  services.tailscale.enable = true;
}
