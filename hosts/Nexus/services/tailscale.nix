{ ... }:
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    interfaceName = "tailscale0";
    useRoutingFeatures = "server";
  };
}
