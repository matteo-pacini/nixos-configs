{ pkgs, config, ... }:
{
  services.grafana = {
    enable = true;

    declarativePlugins = with pkgs.grafanaPlugins; [
      victoriametrics-metrics-datasource
    ];

    settings = {
      users.allow_sign_up = false;

      server = {
        # Loopback only: Caddy terminates TLS and gates by source IP, so Grafana
        # must not be reachable directly on the LAN.
        http_addr = "127.0.0.1";
        http_port = 3000;
        # Must match the Caddy vhost or OAuth redirects, share links and the
        # rendered image URLs all point at the wrong host.
        root_url = "https://grafana.matteopacini.me";
      };

      database = {
        type = "postgres";
        host = "/run/postgresql";
        name = "grafana";
        user = "grafana";
      };

      security = {
        admin_user = "matteo";
        admin_password = "$__file{${config.age.secrets."nexus/grafana-admin-password".path}}";
        admin_email = "m+grafana@matteopacini.me";
        allow_embedding = true;
        secret_key = "$__file{${config.age.secrets."nexus/grafana-secret-key".path}}";
      };
    };

    provision.datasources.settings = {
      apiVersion = 1;
      datasources = [
        {
          name = "VictoriaMetrics";
          type = "victoriametrics-metrics-datasource";
          access = "proxy";
          url = "http://127.0.0.1:8428";
          isDefault = true;
        }
      ];
    };
  };
}
