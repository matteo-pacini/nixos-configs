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
          port = builtins.toString (builtins.head config.services.openssh.ports);
          filter = "sshd";
          maxretry = 3;
        };
      };

      # Caddy general protection (JSON log format)
      caddy-http-auth = {
        settings = {
          enabled = true;
          filter = "caddy-http-auth";
          port = "http,https";
          logpath = "/var/log/caddy/access.log";
          backend = "auto"; # Required for file-based monitoring
          maxretry = 5;
        };
      };

      caddy-botsearch = {
        settings = {
          enabled = true;
          filter = "caddy-botsearch";
          port = "http,https";
          logpath = "/var/log/caddy/access.log";
          backend = "auto"; # Required for file-based monitoring
          maxretry = 2;
        };
      };

      # n8n specific protection
      n8n-auth = {
        settings = {
          enabled = true;
          filter = "n8n-auth";
          port = "http,https";
          logpath = "/var/log/caddy/access.log";
          backend = "auto"; # Required for file-based monitoring
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

      # Nextcloud specific protection
      nextcloud-auth = {
        settings = {
          enabled = true;
          filter = "nextcloud-auth";
          port = "http,https";
          logpath = "/var/log/nextcloud/nextcloud.log";
          backend = "auto";
          maxretry = 3;
          findtime = "43200"; # 12 hours
          bantime = "86400"; # 24 hours
        };
      };

      # Home Assistant specific protection
      hass-auth = {
        settings = {
          enabled = true;
          filter = "hass-auth";
          port = "http,https";
          # Monitor Home Assistant's log file (not nginx logs)
          logpath = "${config.services.home-assistant.configDir}/home-assistant.log";
          backend = "auto"; # Required when monitoring log files
          maxretry = 3;
          findtime = "43200"; # 12 hours
          bantime = "86400"; # 24 hours
        };
      };
    };
  };

  # Custom filter for Caddy HTTP authentication failures (JSON format)
  # Matches 401 (Unauthorized) and 403 (Forbidden) responses
  environment.etc."fail2ban/filter.d/caddy-http-auth.conf".text = ''
    [Definition]
    failregex = "client_ip":"<HOST>"(?:.*)"status":(?:401|403)
    datepattern = "ts":{Epoch}
    ignoreregex =
  '';

  # Custom filter for Caddy bot search attempts (JSON format)
  # Matches 404 (Not Found) and 400 (Bad Request) responses
  # Ignores Home Assistant (has dedicated hass-auth jail)
  environment.etc."fail2ban/filter.d/caddy-botsearch.conf".text = ''
    [Definition]
    failregex = "client_ip":"<HOST>"(?:.*)"status":(?:404|400)
    datepattern = "ts":{Epoch}
    ignoreregex = "host":"home\.matteopacini\.me"
  '';

  # Custom filter for n8n authentication failures (JSON format)
  environment.etc."fail2ban/filter.d/n8n-auth.conf".text = ''
    [Definition]
    failregex = "client_ip":"<HOST>"(?:.*)"uri":".*/rest/login.*"(?:.*)"status":(?:401|403)
                "client_ip":"<HOST>"(?:.*)"uri":".*/rest/.*"(?:.*)"status":401
    datepattern = "ts":{Epoch}
    ignoreregex =
  '';

  # Custom filter for Nextcloud authentication failures
  # Based on official Nextcloud documentation:
  # https://docs.nextcloud.com/server/23/admin_manual/installation/harden_server.html
  # Uses _groupsre to match JSON keys in any order
  environment.etc."fail2ban/filter.d/nextcloud-auth.conf".text = ''
    [Definition]
    _groupsre = (?:(?:,?\s*"\w+":(?:"[^"]+"|\\w+))*?)
    failregex = ^\{%%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%%(_groupsre)s,?\s*"message":"Login failed:
                ^\{%%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%%(_groupsre)s,?\s*"message":"Trusted domain error.
    datepattern = ,?\s*"time"\s*:\s*"%%Y-%%m-%%d[T ]%%H:%%M:%%S(%%z)?"
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

  # Custom filter for Home Assistant authentication failures
  # Based on official Home Assistant documentation: https://www.home-assistant.io/integrations/fail2ban/
  # Monitors Home Assistant's log file for failed login attempts
  environment.etc."fail2ban/filter.d/hass-auth.conf".text = ''
    [INCLUDES]
    before = common.conf

    [Definition]
    failregex = ^%(__prefix_line)s.*Login attempt or request with invalid authentication from <HOST>.*$
    ignoreregex =

    [Init]
    datepattern = ^%%Y-%%m-%%d %%H:%%M:%%S
  '';
}
