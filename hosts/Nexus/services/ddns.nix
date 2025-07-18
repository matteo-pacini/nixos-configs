{ config, ... }:
{
  services.r53-ddns = {
    enable = true;
    zoneID = "Z2W1U3HFCO6M27";
    hostname = "gateway";
    domain = "matteopacini.me";
    interval = "1day";
    environmentFile = config.age.secrets."nexus/route53-env".path;
    ttl = 300;
  };
}
