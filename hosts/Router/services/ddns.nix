{ config, ... }:
{
  services.r53-ddns = {
    enable = true;
    zoneID = "Z1SET0B5O77EHQ";
    hostname = "gateway";
    domain = "codecraft.it";
    interval = "1day";
    environmentFile = config.age.secrets."router/route53-env".path;
  };
}
