{ pkgs, lib, ... }:
let
  jellyfinAllowedIpsFile = "/run/jellyfin-allowed/allowed-ips.conf";
  # This script, once built, will be in the Nix store (read-only).
  # But when it runs, it writes to /run/jellyfin-allowed/allowed-ips.conf, which is mutable.
  updateAllowedIpsScript = pkgs.writeShellScriptBin "update-allowed-ips-4" ''
    #!/usr/bin/env bash
    set -euo pipefail

    PATH=${pkgs.coreutils}/bin:${pkgs.dig}/bin:$PATH

    OUT_FILE="${jellyfinAllowedIpsFile}"
    TMP_FILE="$(mktemp)"

    echo "Generating Nginx IP allowlist in: $OUT_FILE"

    # Helper function to add a single IP
    allow_ip() {
      local ip="$1"
      echo "allow $ip;" >> "$TMP_FILE"
    }

    # Helper that uses dig for a hostname and adds all resolved IPs
    dig_and_allow() {
      local host="$1"
      echo "Resolving $host ..."
      local resolved
      resolved="$(dig +short "$host" A 2>/dev/null || true)"
      if [ -n "$resolved" ]; then
        for ip in $resolved; do
          echo "  Found IP: $ip"
          allow_ip "$ip"
        done
      else
        echo "  No IP found for $host"
      fi
    }

    # Write the header
    echo "#" > "$TMP_FILE"
    echo "# Auto-generated IP allowlist for Nginx" >> "$TMP_FILE"
    echo "# Generated: $(date)" >> "$TMP_FILE"
    echo "#" >> "$TMP_FILE"
    echo "" >> "$TMP_FILE"

    # Manually allow specific IPs
    allow_ip "93.56.135.241"
    allow_ip "93.51.34.207"
    allow_ip "2.196.211.180"

    # Dynamically allow IPs from DNS lookups
    dig_and_allow "vpn.jetos.com"
    dig_and_allow "vipah88182.duckdns.org"

    # Final deny
    echo "" >> "$TMP_FILE"
    echo "deny all;" >> "$TMP_FILE"
    echo "" >> "$TMP_FILE"
    echo "# End of file" >> "$TMP_FILE"

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
    virtualHosts = {
      "gateway.codecraft.it" = {
        enableACME = true;
        forceSSL = true;
        locations."/".extraConfig = ''

          include ${jellyfinAllowedIpsFile};

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

          include ${jellyfinAllowedIpsFile};

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
