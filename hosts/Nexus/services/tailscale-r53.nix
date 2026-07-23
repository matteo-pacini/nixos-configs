{
  config,
  pkgs,
  lib,
  ...
}:
let
  zoneID = "Z2W1U3HFCO6M27"; # matteopacini.me
  record = "nexus-ts.matteopacini.me";
  ttl = 300;

  # Publish Nexus's Tailscale IPv4 as an A record so tailnet hosts can
  # resolve service hostnames (which CNAME to nexus-ts) to a routable
  # 100.x address. The IP is CGNAT/unroutable off-tailnet, so a public
  # record is harmless; Caddy's source-IP gate still enforces access.
  # Versioned name forces a rebuild when the script changes.
  updater = pkgs.writeShellScriptBin "tailscale-r53_1" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        config.services.tailscale.package
        pkgs.awscli2
        pkgs.coreutils
      ]
    }:$PATH

    # tailscaled may not have an IPv4 yet just after boot; retry ~2min.
    ip=""
    for _ in $(seq 1 60); do
      if ip="$(tailscale ip -4 2>/dev/null)" && [ -n "$ip" ]; then
        break
      fi
      ip=""
      sleep 2
    done
    [ -n "$ip" ] || { echo "tailscale IPv4 not available after retries" >&2; exit 1; }
    case "$ip" in
      100.*) : ;;
      *) echo "refusing to publish non-CGNAT address: $ip" >&2; exit 1 ;;
    esac

    aws route53 change-resource-record-sets \
      --hosted-zone-id ${zoneID} \
      --change-batch "{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"${record}\",\"Type\":\"A\",\"TTL\":${toString ttl},\"ResourceRecords\":[{\"Value\":\"$ip\"}]}}]}"

    echo "Route53: ${record} A -> $ip"
  '';
in
{
  systemd.timers."tailscale-r53" = {
    description = "Publish Nexus Tailscale IPv4 to Route53 (nexus-ts)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1day";
      Persistent = true;
      Unit = "tailscale-r53.service";
    };
  };

  systemd.services."tailscale-r53" = {
    description = "Publish Nexus Tailscale IPv4 to Route53 (nexus-ts)";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      # Runs as root (default): the tailscaled local-API socket is
      # root-only, so DynamicUser would be denied.
      ExecStart = lib.getExe updater;
      # AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (IAM user "router"),
      # the same secret used by r53-ddns and Caddy's ACME DNS-01.
      EnvironmentFile = config.age.secrets."nexus/route53-env".path;
      # Route53 is global; pin a region so the CLI never prompts for one.
      Environment = [ "AWS_DEFAULT_REGION=us-east-1" ];
    };
  };
}
