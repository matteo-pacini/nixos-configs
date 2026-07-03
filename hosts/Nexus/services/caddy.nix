{ config, pkgs, ... }:
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

    # Caddy built with the Route53 DNS provider so ACME can solve the
    # DNS-01 challenge instead of HTTP-01 — no inbound port 80 needed.
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/route53@v1.6.2" ];
      hash = "sha256-dxrfc6o6PBxRqMRUDpenHDctHUNQx4ZmAy9577RTTKg=";
    };

    # AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY for the Route53 plugin.
    # Same IAM user (router) and secret already used by r53-ddns.
    environmentFile = config.age.secrets."nexus/route53-env".path;

    # Solve every cert via DNS-01 over Route53. Plugin reads the AWS
    # credentials from the environment (SDK default chain).
    globalConfig = ''
      acme_dns route53
    '';

    # Email for Let's Encrypt ACME registration
    email = "m+acme@matteopacini.me";

    # Virtual hosts
    virtualHosts = {
      "jellyfin.matteopacini.me" = {
        logFormat = ''
          output file /var/log/caddy/access.log
          format json
        '';
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
        logFormat = ''
          output file /var/log/caddy/access.log
          format json
        '';
        extraConfig = ''
          header {
            -Server  # Hide Caddy version (security hardening)
            X-Content-Type-Options nosniff
            -X-Frame-Options  # Strip n8n's X-Frame-Options to allow HA iframe embedding
            Content-Security-Policy "frame-ancestors 'self' https://home.matteopacini.me"
            Referrer-Policy no-referrer
            Strict-Transport-Security "max-age=31536000; includeSubDomains"
          }

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

      "nextcloud.matteopacini.me" = {
        logFormat = ''
          output file /var/log/caddy/access.log
          format json
        '';
        extraConfig = ''
          ${securityHeaders}

          # Large upload limit for file sync
          request_body {
            max_size 16GB
          }

          # Reverse proxy to Nextcloud's internal nginx
          reverse_proxy 127.0.0.1:8085
        '';
      };

      "cache.matteopacini.me" = {
        logFormat = ''
          output file /var/log/caddy/access.log
          format json
        '';
        extraConfig = ''
          ${securityHeaders}

          # Generous limit: the largest NARs (CUDA, kernels) run to a
          # few GB; this just bounds what a single request can stream
          request_body {
            max_size 8GB
          }

          # Reverse proxy to atticd
          reverse_proxy 127.0.0.1:8080
        '';
      };

      "home.matteopacini.me" = {
        logFormat = ''
          output file /var/log/caddy/access.log
          format json
        '';
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

      "design.matteopacini.me" = {
        logFormat = ''
          output file /var/log/caddy/access.log
          format json
        '';
        extraConfig = ''
          ${securityHeaders}

          # LAN-only: no public A record exists, and this gates by source IP
          # (LAN + tailnet) so the shared, WAN-forwarded :443 can't reach it.
          @external not remote_ip 192.168.10.0/24 192.168.20.0/24 100.64.0.0/10 127.0.0.1/8
          respond @external 403

          # Reference images / asset uploads for open-design. Match the
          # daemon's projectUpload ceiling (server.ts: 200MB) so Caddy isn't
          # the artificial bottleneck; leave headroom for multipart
          # framing/boundary overhead.
          request_body {
            max_size 210MB
          }

          # Reverse proxy to the open-design bundled Caddy (SPA + /api,
          # /artifacts, /frames → daemon 7457). flush_interval -1 keeps the
          # SSE artifact stream unbuffered. The bundled Caddy's site is bound
          # to 127.0.0.1:5174 and returns an empty 200 for any other Host, so
          # rewrite the upstream Host (Caddy forwards the original by default).
          reverse_proxy 127.0.0.1:5174 {
            header_up Host 127.0.0.1:5174
            flush_interval -1
          }
        '';
      };
    };
  };
}
