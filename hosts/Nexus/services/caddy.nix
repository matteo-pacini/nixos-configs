{ config, pkgs, ... }:
let
  # n8n's podman network — see the file for why this is not a literal.
  podmanSubnet = import ./n8n/bridge-subnet.nix;

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
      hash = "sha256-Vzp4Y9mARJrAHZ1C3x6+5zTSGiYY1l3FxIPkqK1RI30=";
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

          # LAN + tailnet only. n8n's UI has its own login, but the Paperless
          # document agent is reached through webhook paths that take no
          # credentials, so without this gate the archive is queryable by
          # anyone who learns the URL. Home Assistant calls n8n over loopback
          # (webhook_conversation -> 127.0.0.1:5678), so nothing here needs to
          # be reachable from outside.
          @external not remote_ip 192.168.10.0/24 192.168.20.0/24 100.64.0.0/10 127.0.0.1/8
          respond @external 403

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

      "grafana.matteopacini.me" = {
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

          # Reverse proxy to Grafana (loopback; see services.grafana settings).
          # WebSocket support (live panels) is automatic.
          reverse_proxy 127.0.0.1:${toString config.services.grafana.settings.server.http_port}
        '';
      };

      "metrics.matteopacini.me" = {
        logFormat = ''
          output file /var/log/caddy/access.log
          format json
        '';
        extraConfig = ''
          ${securityHeaders}

          # Read-only window onto VictoriaMetrics for n8n's metrics agent.
          # n8n runs in a podman container, so it cannot reach the archive's
          # loopback listener; this vhost is the only way in.
          #
          # Everything is wrapped in `route` so the directives run top to
          # bottom. Caddy's default ordering puts reverse_proxy after respond
          # but handle before it, and a gate that runs after the thing it
          # guards is not a gate.
          route {
            # LAN, tailnet, the podman bridge, and the host itself. Nothing
            # resolves this name today except n8n's --add-host entry; if a
            # record is ever added it should CNAME to nexus-ts like grafana,
            # and this source-IP gate stays the thing that actually enforces
            # reachability on the shared, WAN-forwarded :443.
            @external not remote_ip 192.168.10.0/24 192.168.20.0/24 100.64.0.0/10 ${podmanSubnet} 127.0.0.1/8
            respond @external 403

            # VictoriaMetrics takes no credentials, so the allowlist is the
            # only thing standing between this vhost and /api/v1/write or
            # /api/v1/admin/tsdb/delete_series. A stray write corrupts a
            # series the recorder can no longer rebuild: it keeps 30 days
            # (see purge_keep_days) and this archive keeps 100 years.
            @readonly path /api/v1/query /api/v1/query_range /api/v1/series /api/v1/labels /api/v1/label/*
            reverse_proxy @readonly 127.0.0.1:${builtins.elemAt (builtins.split ":" config.services.victoriametrics.listenAddress) 2}

            respond "victoriametrics: read-only proxy" 403
          }
        '';
      };

      "docs.matteopacini.me" = {
        logFormat = ''
          output file /var/log/caddy/access.log
          format json
        '';
        extraConfig = ''
          ${securityHeaders}

          # LAN + tailnet only. The name CNAMEs to nexus-ts, a 100.x address
          # nothing off-tailnet can route, and this source-IP gate is what
          # keeps the shared, WAN-forwarded :443 off the document archive.
          @external not remote_ip 192.168.10.0/24 192.168.20.0/24 100.64.0.0/10 127.0.0.1/8
          respond @external 403

          # Documents are uploaded whole through the web UI; the ceiling has
          # to clear the largest scan.
          request_body {
            max_size 1GB
          }

          # Reverse proxy to Paperless (port tracks services.paperless.port).
          # WebSocket (/ws/status consumer progress) is automatic.
          reverse_proxy 127.0.0.1:${toString config.services.paperless.port}
        '';
      };

      "photos.matteopacini.me" = {
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

          # Immich uploads each asset in a single request (no client-side
          # chunking), so the ceiling must clear the largest video/motion
          # photo. Generous, matching the other large-upload hosts.
          request_body {
            max_size 20GB
          }

          # Reverse proxy to Immich (port tracks services.immich.port)
          # WebSocket support (real-time events) is automatic
          reverse_proxy 127.0.0.1:${toString config.services.immich.port}
        '';
      };
    };
  };
}
