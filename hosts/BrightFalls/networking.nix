_:
{
  networking.hostName = "BrightFalls";

  networking.firewall.enable = true;

  networking.networkmanager.enable = true;

  # Enable Wake-on-LAN for the Ethernet interface
  networking.interfaces.enp2s0.wakeOnLan.enable = true;

  # IPv6 disabled

  networking.enableIPv6 = false;

  services.tailscale.enable = true;
}
