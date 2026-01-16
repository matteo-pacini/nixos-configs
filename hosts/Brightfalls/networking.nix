{ lib, isVM, ... }:
{
  networking.hostName = "BrightFalls${if isVM then "VM" else ""}";

  networking.firewall.enable = true;

  networking.networkmanager.enable = true;

  # Enable Wake-on-LAN for the Ethernet interface
  networking.interfaces.enp2s0.wakeOnLan.enable = lib.mkIf (!isVM) true;

  # IPv6 disabled

  networking.enableIPv6 = false;

  services.tailscale.enable = lib.mkIf (!isVM) true;

}
