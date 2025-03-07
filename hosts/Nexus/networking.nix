{ lib, ... }:
{
  networking.hostName = "Nexus";

  networking.firewall.enable = false;

  networking.useDHCP = lib.mkDefault false;

  networking.interfaces.eno1.ipv4.addresses = [
    {
      address = "192.168.7.7";
      prefixLength = 24;
    }
  ];

  networking.defaultGateway = "192.168.7.1";
  networking.nameservers = [ "192.168.7.1" ];

  services.tailscale.enable = true;

}
