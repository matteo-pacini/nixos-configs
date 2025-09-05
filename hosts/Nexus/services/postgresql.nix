{ ... }:
{
  services.postgresql = {
    enable = true;
    ensureDatabases = [
      "hass"
      "grafana"
    ];
    ensureUsers = [
      {
        name = "hass";
        ensureDBOwnership = true;
      }
      {
        name = "grafana";
        ensureDBOwnership = true;
      }
    ];
  };
}
