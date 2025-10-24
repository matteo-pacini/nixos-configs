{ pkgs, config, ... }:
{
  services.grafana = {
    enable = true;
    declarativePlugins = with pkgs.grafanaPlugins; [
      victoriametrics-metrics-datasource
      victoriametrics-logs-datasource
    ];
    settings = {
      users.allow_sign_up = false;
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        root_url = "https://grafana.matteopacini.me";
        serve_from_sub_path = true;
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
        cookie_secure = true;
        cookie_samesite = "Lax";
      };
    };
    provision.dashboards.settings.providers = [
      {
        name = "Overview";
        options.path = "/etc/grafana-dashboards";
      }
    ];
    provision.datasources = {
      settings = {
        apiVersion = 1;
        datasources = [
          {
            name = "VictoriaMetrics";
            type = "victoriametrics-metrics-datasource";
            access = "proxy";
            url = "http://127.0.0.1:8428";
            isDefault = true;
          }

          {
            name = "VictoriaLogs";
            type = "victoriametrics-logs-datasource";
            access = "proxy";
            url = "http://127.0.0.1:9428";
            isDefault = false;
          }
        ];
      };
    };
  };
}
