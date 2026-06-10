{ ... }:
{
  services.atuin = {
    enable = true;
    openRegistration = false;
    openFirewall = false;
    host = "0.0.0.0";
    port = 8888;
    database.createLocally = true;
  };

  # WorkLaptop has no Tailscale (corp policy) and syncs over the LAN, so
  # allow 8888 from the LAN subnet only instead of openFirewall's
  # all-interfaces rule. Tailnet clients come in via trustedInterfaces.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.10.0/24 tcp dport 8888 accept
  '';
}
