{ config, ... }:
{
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    ignoreIP = [
      # Localhost
      "127.0.0.0/8"
      "::1"
      # LAN networks
      "192.168.10.0/24" # HOME VLAN
      "192.168.20.0/24" # GUEST VLAN
    ];
    bantime = "1h";
    bantime-increment = {
      enable = true;
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "1536h"; # 64 days
      overalljails = true;
    };

    jails = {
      # SSH protection
      sshd = {
        settings = {
          enabled = true;
          port = "1788";
          filter = "sshd";
          maxretry = 3;
        };
      };

      # nginx general protection
      nginx-http-auth = {
        settings = {
          enabled = true;
          filter = "nginx-http-auth";
          port = "http,https";
          logpath = "/var/log/nginx/error.log";
        };
      };

      nginx-botsearch = {
        settings = {
          enabled = true;
          filter = "nginx-botsearch";
          port = "http,https";
          logpath = "/var/log/nginx/access.log";
          maxretry = 2;
        };
      };

      # n8n specific protection
      n8n-auth = {
        settings = {
          enabled = true;
          filter = "n8n-auth";
          port = "http,https";
          logpath = "/var/log/nginx/access.log";
          maxretry = 3;
          findtime = "43200"; # 12 hours
          bantime = "86400"; # 24 hours
        };
      };

      # Jellyfin specific protection
      jellyfin-auth = {
        settings = {
          enabled = true;
          filter = "jellyfin-auth";
          port = "http,https";
          # Monitor Jellyfin's native log files (not nginx logs)
          logpath = "${config.services.jellyfin.logDir}/*.log";
          backend = "auto"; # Required when monitoring log files
          maxretry = 3;
          findtime = "43200"; # 12 hours (as recommended by Jellyfin docs)
          bantime = "86400"; # 24 hours (as recommended by Jellyfin docs)
        };
      };
    };
  };

  # Custom filter for n8n authentication failures
  environment.etc."fail2ban/filter.d/n8n-auth.conf".text = ''
    [Definition]
    failregex = ^<HOST> .* "(GET|POST) .*/rest/login.*" (401|403) .*$
                ^<HOST> .* "(GET|POST) .*/rest/.*" 401 .*$
    ignoreregex =
  '';

  # Custom filter for Jellyfin authentication failures
  # Based on official Jellyfin documentation: https://jellyfin.org/docs/general/post-install/networking/advanced/fail2ban/
  # Monitors Jellyfin's native log files for failed authentication attempts
  environment.etc."fail2ban/filter.d/jellyfin-auth.conf".text = ''
    [Definition]
    failregex = ^.*Authentication request for .* has been denied \(IP: "<ADDR>"\)\.
    ignoreregex =
  '';
}
