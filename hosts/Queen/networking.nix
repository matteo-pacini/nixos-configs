{ ... }:
{
  networking.hostName = "Queen";

  networking.firewall.enable = false;

  networking.networkmanager.enable = true;

  # IPv6 disabled

  networking.enableIPv6 = false;

  services.tailscale.enable = true;

}
