{ config, ... }:
{
  security.acme = {
    acceptTerms = true;
    defaults.email = "m+acme@matteopacini.me";
    certs."gateway.codecraft.it" = {
      group = "acme";
      dnsProvider = "route53";
      environmentFile = config.age.secrets."router/route53-env".path;
    };
  };
}
