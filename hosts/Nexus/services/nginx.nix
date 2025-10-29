{ ... }:
{

  services.nginx = {
    enable = true;
    clientMaxBodySize = "20M";
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    logError = "stderr info";
    virtualHosts = {
      "n8n.matteopacini.me" = {
        enableACME = true;
        forceSSL = true;
        locations."/".extraConfig = ''
          # Protected by fail2ban - no IP restrictions needed
          proxy_pass http://127.0.0.1:5678;
          proxy_http_version 1.1;
          proxy_set_header Connection 'Upgrade';
          proxy_set_header Upgrade $http_upgrade;

          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Protocol $scheme;
          proxy_set_header X-Forwarded-Host $http_host;
        '';
        locations."~ ^/(webhook|webhook-test)(/|$)" = {
          extraConfig = ''
            proxy_pass        http://127.0.0.1:5678$request_uri;

            proxy_set_header  Host              $host;
            proxy_set_header  X-Real-IP         $remote_addr;
            proxy_set_header  X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header  X-Forwarded-Proto $scheme;

            client_max_body_size 16M;
          '';
        };
        locations."~ ^/(mcp|mcp-test)(/|$)" = {
          extraConfig = ''
            proxy_pass        http://127.0.0.1:5678$request_uri;

            proxy_set_header  Host              $host;
            proxy_set_header  X-Real-IP         $remote_addr;
            proxy_set_header  X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header  X-Forwarded-Proto $scheme;

            client_max_body_size 16M;
          '';
        };
      };
      "home.matteopacini.me" = {
        enableACME = true;
        forceSSL = true;
        extraConfig = ''
          proxy_buffering off;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:8123";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $http_host;
            proxy_set_header X-Forwarded-Server $hostname;

            # Connection settings for long-lived WebSocket connections
            proxy_read_timeout 86400;
            proxy_send_timeout 86400;
          '';
        };
        locations."/radarr" = {
          proxyPass = "http://127.0.0.1:7878";
          extraConfig = ''
            # Restrict access to local networks only (HOME and GUEST VLANs)
            allow 192.168.10.0/24; # HOME VLAN
            allow 192.168.20.0/24; # GUEST VLAN
            deny all;

            # Proxy headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $http_host;
          '';
        };
        locations."/sonarr" = {
          proxyPass = "http://127.0.0.1:8989";
          extraConfig = ''
            # Restrict access to local networks only (HOME and GUEST VLANs)
            allow 192.168.10.0/24; # HOME VLAN
            allow 192.168.20.0/24; # GUEST VLAN
            deny all;

            # Proxy headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $http_host;
          '';
        };
        locations."/nzbhydra2" = {
          proxyPass = "http://127.0.0.1:5076/nzbhydra2";
          extraConfig = ''
            # Restrict access to local networks only (HOME and GUEST VLANs)
            allow 192.168.10.0/24; # HOME VLAN
            allow 192.168.20.0/24; # GUEST VLAN
            deny all;

            # Proxy headers (from NZBHydra2 documentation)
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header Host $host;
            proxy_set_header Scheme $scheme;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_redirect off;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
          '';
        };

      };
      "nzbget.matteopacini.me" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:6789";
          extraConfig = ''
            # Restrict access to local networks only (HOME and GUEST VLANs)
            allow 192.168.10.0/24; # HOME VLAN
            allow 192.168.20.0/24; # GUEST VLAN
            deny all;

            # Proxy headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };
      "jellyfin.matteopacini.me" = {
        enableACME = true;
        forceSSL = true;
        locations."/".extraConfig = ''
          # Proxy main Jellyfin traffic
          proxy_pass http://127.0.0.1:8096;
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
          proxy_pass http://127.0.0.1:8096;
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
