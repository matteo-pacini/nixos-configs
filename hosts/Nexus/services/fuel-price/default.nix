{ config, pkgs, ... }:
let
  fuelPrice = pkgs.writers.writePython3Bin "fuel-price" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./fuel_price.py);

  # Runs as hass: Home Assistant's command_line sensors read the JSON these
  # write to /var/lib/fuel-price.
  common = {
    Type = "oneshot";
    User = "hass";
    Group = "hass";
    StateDirectory = "fuel-price";
    StateDirectoryMode = "0750";
    ProtectSystem = "strict";
    PrivateTmp = true;
    NoNewPrivileges = true;
  };
in
{
  # Local E10 price at the station we fill up at. The station id is a secret
  # only because it says where we live.
  systemd.services.fuel-price-poll = {
    description = "Fetch the local E10 price from Fuel Finder";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = common // {
      LoadCredential = [
        "fuel-finder:${config.age.secrets."nexus/fuel-finder".path}"
        "fuel-finder-station:${config.age.secrets."nexus/fuel-finder-station".path}"
      ];
      ExecStart = "${fuelPrice}/bin/fuel-price poll";
    };
  };
  systemd.timers.fuel-price-poll = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:00/30";
      RandomizedDelaySec = "2min";
      Persistent = true;
    };
  };

  # Monthly fuel spend and projection, from the car's history in
  # VictoriaMetrics and the weekly national price.
  systemd.services.fuel-price-cost = {
    description = "Work out monthly fuel cost for the car view";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "victoriametrics.service"
      "fuel-price-poll.service"
    ];
    serviceConfig = common // {
      ExecStart = "${fuelPrice}/bin/fuel-price cost";
    };
  };
  systemd.timers.fuel-price-cost = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "5min";
      Persistent = true;
    };
  };
}
