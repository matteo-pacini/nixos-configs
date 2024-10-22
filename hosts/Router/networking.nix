{ pkgs, lib, ... }:
let
  jellyfinAllowedHostsUpdateScript = (
    pkgs.writeShellScriptBin "jellyfin-allowed-hosts-update-script-4" ''
      set -eo pipefail
      PATH=${pkgs.nftables}/bin:${pkgs.dig}/bin:$PATH

      echo "Flushing jellyfin-allowed ipset..."
      nft flush set inet filter jellyfin-allowed

      add() {
        echo "Processing IP entry '$1'..."
        if [ -n "$1" ]; then  # Check if IP is not empty
          nft add element inet filter jellyfin-allowed { $1 } 
          echo "Added IP '$1'"
        else
          echo "No valid IP provided."
        fi
      }

      dig_and_add() {
        echo "Processing DIG entry '$1'..."
        local IP=$(dig +short "$1" 2> /dev/null)

        if [ -n "$IP" ]; then  # Check if DIG found an IP
          echo "Found IP $IP - whitelisting..."
          nft add element inet filter jellyfin-allowed { $IP } 
        else
          echo "No IP found for '$1', skipping entry..."
        fi
      }

      # EDIT HERE

      add "93.56.135.241"                   # Medic
      add "93.51.34.207"                    # Roma
      add "2.196.211.180"                   # Sondalo
      dig_and_add "vpn.jetos.com"
      dig_and_add "vipah88182.duckdns.org"

      # END EDIT

      echo "State:"
      nft list set inet filter jellyfin-allowed

      echo "Done!"

    ''
  );
in
{
  networking.hostName = "Router";

  networking = {

    enableIPv6 = false;

    nat.enable = false;
    firewall.enable = false;
    nftables = {
      enable = true;
      ruleset = ''

        table inet filter {

            set jellyfin-allowed {
              type ipv4_addr;
              flags dynamic;
            }

            chain output {
              type filter hook output priority 0; policy accept;
            }

            chain input {
              type filter hook input priority 0; policy drop;

              # Localhost
              iifname "lo" accept

              # Allow LAN traffic
              iifname "eno4" counter accept

              # Allow 443 and 80 from jellyfin-allowed hosts (WAN)
              iifname "enp6s0f0" ip saddr @jellyfin-allowed tcp dport { 443, 80 } counter accept

              # Allow returning traffic from WAN and drop everthing else
              iifname "enp6s0f0" ct state { established, related } counter accept
              iifname "enp6s0f0" log prefix "Dropped from WAN: " limit rate 2/minute counter drop
          }

          chain forward {
            type filter hook forward priority 0; policy drop;

            # Allow LAN to WAN traffic
            iifname "eno4" oifname "enp6s0f0" counter accept

            # Allow established WAN to LAN traffic
            iifname "enp6s0f0" oifname "eno4" ct state established,related counter accept
          }
        }
          
        table ip nat {

          chain prerouting {
            type nat hook prerouting priority 0; policy accept;
          }

          chain postrouting {
            type nat hook postrouting priority 0; policy accept;

            # Setup NAT masquerading on the WAN interface
            oifname "enp6s0f0" masquerade
          }
        }
      '';
    };

    useDHCP = false;

    interfaces = {

      # DHCP
      enp6s0f0.useDHCP = true;

      eno4.useDHCP = false;
      eno4 = {
        ipv4.addresses = [
          {
            address = "192.168.7.1";
            prefixLength = 24;
          }
        ];
      };

    };
  };

  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = true;
    alwaysKeepRunning = true;
    settings = {
      dhcp-range = "eno4,192.168.7.150,192.168.7.250,24h";
      server = [
        "1.1.1.1"
        "1.0.0.1"
      ];
      domain-needed = true;
      bogus-priv = true;
    };
  };

  systemd.timers."update-jellyfin-ipset" = {
    description = "Update jellyfin allowed hosts ipset (timer)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "30min";
      Unit = "update-jellyfin-ipset.service";
    };
  };

  systemd.services = {
    "update-jellyfin-ipset" = {
      description = " Update jellyfin allowed hosts ipset";
      serviceConfig = {
        User = "root";
        Type = "oneshot";
        ExecStart = "${lib.getExe jellyfinAllowedHostsUpdateScript}";
      };
    };
  };

}
