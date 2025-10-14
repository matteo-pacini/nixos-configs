{ lib, isVM, ... }:
{
  networking.hostName = "BrightFalls${if isVM then "VM" else ""}";

  networking.firewall.enable = false;

  networking.networkmanager.enable = true;

  # IPv6 disabled

  networking.enableIPv6 = false;

  services.tailscale.enable = lib.mkIf (!isVM) true;

}
