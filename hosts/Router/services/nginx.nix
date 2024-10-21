{ ... }:
{
  services.nginx = {
    enable = true;
    appendHttpConfig = ''
      client_max_body_size 20M;

      # Allow modern TLS protocols only
      ssl_protocols TLSv1.3 TLSv1.2;

      # Security / XSS Mitigation Headers 
      add_header X-Frame-Options "SAMEORIGIN";
      add_header X-XSS-Protection "0"; # Do NOT enable. This is obsolete/dangerous
      add_header X-Content-Type-Options "nosniff";

      # Permissions policy. May cause issues with some clients
      add_header Permissions-Policy "accelerometer=(), ambient-light-sensor=(), battery=(), bluetooth=(), camera=(), clipboard-read=(), display-capture=(), document-domain=(), encrypted-media=(), gamepad=(), geolocation=(), gyroscope=(), hid=(), idle-detection=(), interest-cohort=(), keyboard-map=(), local-fonts=(), magnetometer=(), microphone=(), payment=(), publickey-credentials-get=(), serial=(), sync-xhr=(), usb=(), xr-spatial-tracking=()" always;

      # Content Security Policy
      # See: https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP
      # Enforces https content and restricts JS/CSS to origin
      # External Javascript (such as cast_sender.js for Chromecast) must be whitelisted.
      # NOTE: The default CSP headers may cause issues with the webOS app
      add_header Content-Security-Policy "default-src https: data: blob
    '';
    virtualHosts = {
      "gateway.codecraft.it" = {
        forceSSL = true;
        enableACME = true;
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
