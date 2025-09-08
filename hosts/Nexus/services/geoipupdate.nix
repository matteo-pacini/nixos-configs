{ config, ... }:
{
  services.geoipupdate.enable = true;
  services.geoipupdate.settings = {
    EditionIDs = [
      "GeoLite2-ASN"
      "GeoLite2-City"
      "GeoLite2-Country"
    ];
    AccountID = 1223881;
    LicenseKey = config.age.secrets."nexus/geoip-license-key".path;
  };
}
