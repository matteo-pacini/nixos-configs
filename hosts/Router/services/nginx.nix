{ config, ... }:
{
  services.nginx = {
    enable = true;
    clientMaxBodySize = "20M";
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    virtualHosts = {
      "gateway.codecraft.it" = {
        enableACME = true;
        forceSSL = true;
        locations."/".extraConfig = ''
          # Proxy main Jellyfin traffic
          proxy_pass http://192.168.7.7:8096;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Protocol $scheme;
          proxy_set_header X-Forwarded-Host $http_host;

          # Disable buffering when the nginx proxy gets very resource heavy upon streaming
          proxy_buffering off;
        '';
        locations."/socket".extraConfig = ''
          # Proxy Jellyfin Websockets traffic
          proxy_pass http://192.168.7.7:8096;
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Protocol $scheme;
          proxy_set_header X-Forwarded-Host $http_host;
        '';
      };
    };
  };

}
