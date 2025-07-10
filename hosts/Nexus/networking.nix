{ lib, ... }:
{
  networking.hostName = "Nexus";

  networking.firewall.enable = false;

  networking = {
    useDHCP = false;
    useNetworkd = true;
    interfaces.eno1.useDHCP = true;
  };

  services.tailscale.enable = true;

}
