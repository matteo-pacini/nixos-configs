{ ... }:
{
  networking.hostName = "BrightFalls";

  networking.firewall.enable = false;

  networking.networkmanager.enable = true;

  # IPv6 disabled

  networking.enableIPv6 = false;

  services.tailscale.enable = true;

}
