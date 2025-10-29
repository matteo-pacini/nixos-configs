{ ... }:
let
  # Security headers applied to all virtual hosts
  securityHeaders = ''
    header {
      -Server  # Hide Caddy version (security hardening)
      X-Content-Type-Options nosniff
      X-Frame-Options SAMEORIGIN
      Referrer-Policy no-referrer
      Strict-Transport-Security "max-age=31536000; includeSubDomains"
    }
  '';
in
{
  services.caddy = {
    enable = true;

    # Email for Let's Encrypt ACME registration
    email = "m+acme@matteopacini.me";

    # Global configuration
    globalConfig = ''
      # Single access log in Common Log Format for fail2ban compatibility
      log {
        output file /var/log/caddy/access.log
        format transform "{common_log}"
      }

      # Error logging
      log {
        output file /var/log/caddy/error.log
        level ERROR
      }
    '';

    # Virtual hosts
    virtualHosts = {
      "jellyfin.matteopacini.me" = {
        extraConfig = ''
          ${securityHeaders}

          # Limit request body size (streaming only, no large uploads expected)
          request_body {
            max_size 10MB
          }

          # Reverse proxy to Jellyfin
          # WebSocket support is automatic
          reverse_proxy 127.0.0.1:8096
        '';
      };

      "n8n.matteopacini.me" = {
        extraConfig = ''
          ${securityHeaders}

          # Larger limit for workflow imports/exports and webhook payloads
          request_body {
            max_size 16MB
          }

          # Reverse proxy to n8n
          # WebSocket support is automatic
          # All proxy headers set automatically
          reverse_proxy 127.0.0.1:5678
        '';
      };

      "home.matteopacini.me" = {
        extraConfig = ''
          ${securityHeaders}

          # Moderate limit for backups and configuration uploads
          request_body {
            max_size 50MB
          }

          # Reverse proxy to Home Assistant
          # WebSocket support is automatic
          # Long-lived connections handled automatically
          reverse_proxy 127.0.0.1:8123
        '';
      };
    };
  };
}
