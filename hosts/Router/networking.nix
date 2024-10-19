{ lib, ... }:
{
  networking.hostName = "Router";

  networking = {

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

            # Allow trusted networks to access the router
            iifname {
              "lan",
            } counter accept

            # Allow returning traffic from WAN and drop everthing else
            iifname "wan" ct state { established, related } counter accept
            iifname "wan" drop
        }

        chain forward {
          type filter hook forward priority filter; policy drop;

          # Allow trusted network WAN access
          iifname {
            "lan",
          } oifname {
            "wan",
          } counter accept comment "Allow trusted LAN to WAN"

          # Allow established WAN to return
          iifname {
            "wan",
          } oifname {
            "lan",
          } ct state established,related counter accept comment "Allow established back to LANs"
        }

        table ip nat {
          chain prerouting {
            type nat hook prerouting priority filter; policy accept;
          }

          # Setup NAT masquerading on the WAN interface
          chain postrouting {
            type nat hook postrouting priority filter; policy accept;
            oifname "wan" masquerade
          }
        }

      }
    '';

    useDHCP = false;

    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
    ];

    vlans = {
      wan = {
        id = 10;
        interface = "enp6s0f0";
      };
      lan = {
        id = 20;
        interface = "eno4";
      };
    };

    interfaces = {

      # DHCP
      enp6s0f0.useDHCP = true;
      eno4.useDHCP = false;

      lan = {
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
    servers = [
      "1.1.1.1"
      "1.0.0.1"
    ];
    settings = ''
      dhcp-range=lan,192.168.7.150,192.168.7.250,24h
      interface=lan
    '';
  };

}
