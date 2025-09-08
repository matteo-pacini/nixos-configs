{
  pkgs,
  lib,
  config,
  ...
}:
let
  jellyfinAllowedIpsFile = "/run/jellyfin-allowed/allowed-ips.conf";
  # This script, once built, will be in the Nix store (read-only).
  # But when it runs, it writes to /run/jellyfin-allowed/allowed-ips.conf, which is mutable.
  updateAllowedIpsScript = pkgs.writeShellScriptBin "update-allowed-ips-6" ''
    #!/usr/bin/env bash
    set -euo pipefail

    PATH=${pkgs.coreutils}/bin:${pkgs.dig}/bin:$PATH

    OUT_FILE="${jellyfinAllowedIpsFile}"
    TMP_FILE="$(mktemp)"

    echo "Generating Nginx IP allowlist in: $OUT_FILE"

    # Helper function to validate if a string is a valid IPv4 address
    is_valid_ipv4() {
      [[ $1 =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])$ ]]
    }

    # Helper function to add a single IP
    allow_ip() {
      local ip="$1"
      if is_valid_ipv4 "$ip"; then
        echo "allow $ip;" >> "$TMP_FILE"
        return 0
      else
        echo "WARNING: Invalid IP address: $ip - skipping"
        return 1
      fi
    }

    # Helper that uses dig for a hostname and adds all resolved IPs
    dig_and_allow() {
      local host="$1"
      echo "Resolving $host ..."
      
      # Get all results from dig
      local resolved
      resolved="$(dig +short "$host" A 2>/dev/null || true)"
      
      if [ -n "$resolved" ]; then
        local added=0
        for ip in $resolved; do
          if is_valid_ipv4 "$ip"; then
            echo "  Found valid IP: $ip"
            allow_ip "$ip"
            added=$((added + 1))
          else
            echo "  Found invalid IP: $ip - skipping"
          fi
        done
        
        if [ $added -eq 0 ]; then
          echo "  WARNING: No valid IPs found for $host"
        else
          echo "  Successfully added $added IP(s) for $host"
        fi
      else
        echo "  WARNING: DNS resolution failed for $host"
      fi
    }

    # Write the header
    echo "#" > "$TMP_FILE"
    echo "# Auto-generated IP allowlist for Nginx" >> "$TMP_FILE"
    echo "# Generated: $(date)" >> "$TMP_FILE"
    echo "#" >> "$TMP_FILE"
    echo "" >> "$TMP_FILE"

    # Manually allow specific IPs
    # Rome, Iliad
    allow_ip "81.56.209.87"

    # Dynamically allow IPs from DNS lookups
    dig_and_allow "vpn.jetos.com"
    dig_and_allow "vipah88182.duckdns.org"

    # Atomic replace
    mv "$TMP_FILE" "$OUT_FILE"

    echo "Done. Contents of $OUT_FILE:"
    cat "$OUT_FILE"

    # Set public readable permissions
    chmod 644 "$OUT_FILE"

  '';
in
{

  systemd.tmpfiles.rules = [
    "d /run/jellyfin-allowed 0755 root root -"
  ];

  systemd.services."update-allowed-ips" = {
    description = "Generate IP allow-list for Nginx";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe updateAllowedIpsScript}";
      ExecStartPost = "${pkgs.systemd}/bin/systemctl restart nginx.service";
      User = "root";
    };
  };

  systemd.timers."update-allowed-ips" = {
    description = "Generate IP allow-list for Nginx (timer)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Runs 1 min after boot, and every 30 min thereafter
      OnBootSec = "1min";
      OnUnitActiveSec = "30min";
      Unit = "update-allowed-ips.service";
    };
  };

  services.nginx = {
    enable = true;
    clientMaxBodySize = "20M";
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    additionalModules = with pkgs.nginxModules; [
      geoip2
    ];
    commonHttpConfig = ''
      geoip2 ${config.services.geoipupdate.settings.DatabaseDirectory}/GeoLite2-Country.mmdb {
        $geoip2_data_country_iso_code country iso_code;
      }

      map $geoip2_data_country_iso_code $is_country_ok {
        default 0;
        IT 1;
        GB 1;
      }

      geo $is_lan {
        default 0;
        127.0.0.1/32 1;
        ::1/128      1;
        192.168.10.0/24 1; # HOME VLAN
        192.168.20.0/24 1; # GUEST VLAN
      }

      map "$is_lan:$is_country_ok" $block_geo {
        default 1;   # block
        "1:0" 0;     # LAN: allow
        "1:1" 0;     # LAN: allow
        "0:1" 0;     # Allowed country: allow
      }
    '';
    virtualHosts = {
      "home.matteopacini.me" = {
        enableACME = true;
        forceSSL = true;
        extraConfig = ''
          if ($block_geo) { return 403; }
          proxy_buffering off;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:8123";
          proxyWebsockets = true;
        };
      };
      "jellyfin.matteopacini.me" = {
        enableACME = true;
        forceSSL = true;
        locations."/".extraConfig = ''

          allow 192.168.10.0/24;
          include ${jellyfinAllowedIpsFile};
          deny all;

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

          allow 192.168.10.0/24;
          include ${jellyfinAllowedIpsFile};
          deny all;

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
