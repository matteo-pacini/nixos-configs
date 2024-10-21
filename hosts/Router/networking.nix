{ ... }:
{
  networking.hostName = "Router";

  networking = {

    enableIPv6 = false;

    nat.enable = false;
    firewall.enable = false;
    nftables = {
      enable = true;
    };

    nftables.ruleset = ''
      table inet filter {

          chain output {
            type filter hook output priority 100; policy accept;
          }

          chain input {
            type filter hook input priority filter; policy drop;

            # Localhost
            ip saddr 127.0.0.1 accept
            ip daddr 127.0.0.1 accept

            # Allow trusted networks to access the router
            iifname {
              "eno4",
            } counter accept

            # Allow 443 and 80 from WAN
            iifname "enp6s0f0" tcp dport { 443, 80 } counter accept

            # Allow returning traffic from WAN and drop everthing else
            iifname "enp6s0f0" ct state { established, related } counter accept
            iifname "enp6s0f0" drop
        }

        chain forward {
          type filter hook forward priority filter; policy drop;

          # Allow trusted network WAN access
          iifname {
            "eno4",
          } oifname {
            "enp6s0f0",
          } counter accept comment "Allow trusted LAN to WAN"

          # Allow established WAN to return
          iifname {
            "enp6s0f0",
          } oifname {
            "eno4",
          } ct state established,related counter accept comment "Allow established back to LANs"
        }
      }
        
      table ip nat {

        chain prerouting {
          type nat hook prerouting priority filter; policy accept;
        }

        # Setup NAT masquerading on the WAN interface
        chain postrouting {
          type nat hook postrouting priority filter; policy accept;
          oifname "enp6s0f0" masquerade
        }
      }
    '';

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

}
